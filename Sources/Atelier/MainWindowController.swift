import AppKit
import AtelierIPC

/// Direction for the `⌃⌘+hjkl` focus manager.
enum FocusDirection { case left, right, up, down }

/// The mantle wash under the titlebar / native project tab strip (§3.1).
/// Mirrors the field surfaces' translucency handling.
private final class TitlebarWashView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: Settings.didChange,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    /// The hidden-title titlebar passes clicks through to this wash, so the
    /// system's double-click-titlebar action has to be re-spoken here:
    /// zoom (the default), or minimize when the user has set it so.
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2, let window else {
            super.mouseDown(with: event)
            return
        }
        let action = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleActionOnDoubleClick"] as? String
        switch action {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}

/// The app's window class: reports first-responder changes so the focus
/// articulation (hairline + caret truth) can track clicks as well as chords.
final class AtelierWindow: NSWindow {
    var onFirstResponderChange: (() -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted { onFirstResponderChange?() }
        return accepted
    }

}

/// One project window: hosts *sessions* (each an instance of the fixed pane
/// shape), shows one at a time, and carries the bottom bar with the session
/// tab strip (MILESTONE_1 §2, §7). Projects are native tabbed windows
/// (`tabbingMode = .preferred`); persistence snapshots/restores the whole
/// window → session tree (§9); overlays (chooser, palette, ⌘P, ⌘⇧F) mount on the
/// content view and restore pre-overlay focus on dismissal.
final class MainWindowController: NSWindowController, BottomBarDelegate {
    private var sessions: [Session] = []
    private var activeIndex = 0
    private var processesStarted = false

    /// The primary checkout this window's project is anchored to — set when the
    /// first IDE session lands. The `atelier` CLI routes commands by this.
    private(set) var projectRepoRoot: String?

    private let sessionArea = NSView()
    private let bottomBar = BottomBar()
    private var bottomBarHeight: NSLayoutConstraint?
    private var titleTimer: Timer?

    /// Sessions closed from this window, oldest → newest — `⌘⇧T` reopens the
    /// most recent. A close keeps the session *alive but hidden* for a grace
    /// window: reopening inside it re-adopts the exact session (shell state
    /// and all, and no race against the dying claude process, which
    /// otherwise rejects `--resume` with "session already in use"; owner-hit
    /// bug 2026-07-13). After the grace it's terminated and downgraded to a
    /// snapshot that resumes via `--resume`. In-memory by design: the stack
    /// dies with the window, like a browser's.
    private enum ClosedEntry {
        case live(Session, index: Int)
        case snapshot(PersistedSession, index: Int)
    }
    private var recentlyClosed: [ClosedEntry] = []
    private static let closeGrace: TimeInterval = 60
    /// The Landing auto-created when the last session closed. If it's still the
    /// only tab when a reopen lands, the reopen replaces it — the gesture is an
    /// undo, and undo restores the exact prior state.
    private weak var landingFromRevert: Session?

    private var activeSession: Session? {
        sessions.indices.contains(activeIndex) ? sessions[activeIndex] : nil
    }

    /// `root == nil` opens as a Landing (a new project tab); a path opens the
    /// project directly (the CLI's `atelier <path>`).
    convenience init(root: String? = nil) {
        self.init(chrome: ())
        if let root {
            adopt(Session(ideRoot: root))
        } else {
            addSession()
        }
    }

    /// Rebuild a window from a snapshot (sessions are pre-validated by the caller).
    convenience init(restored: PersistedWindow) {
        self.init(chrome: ())
        for persisted in restored.sessions {
            adopt(Session(restored: persisted))
        }
        if sessions.isEmpty {
            addSession()
        } else if sessions.indices.contains(restored.activeIndex) {
            showSession(at: restored.activeIndex)
        }
    }

    /// Shared window + chrome setup; sessions are the caller's job.
    private convenience init(chrome: Void) {
        let window = AtelierWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "New Tab"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // §2.9: transparent, native blur — the aesthetic is a spec
        // requirement. The titlebar region still reads mantle via
        // TitlebarWashView, translucent over the blur like every field
        // surface.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        // Projects are native window tabs (MILESTONE_1 §2): the OS draws the
        // always-visible project strip in the titlebar.
        window.tabbingMode = .preferred

        // The blur is the WindowServer's, not a material (see
        // WindowBlur.swift): NSVisualEffectView materials carry their own
        // near-opaque tint, and two attempts at "more translucent" materials
        // still compounded to a window the owner read as fully opaque. The
        // content view is a bare clear container; the fields' fieldAlpha
        // wash over the blurred desktop is the whole look — Ghostty's
        // pipeline, which is the target feel.
        let container = NSView()
        container.wantsLayer = true
        window.contentView = container
        window.appearance = NSAppearance(named: .darkAqua)

        self.init(window: window)
        window.center()
        window.setFrameAutosaveName("AtelierMainWindow")
        if !WindowBackgroundBlur.apply(to: window, radius: Theme.backgroundBlurRadius) {
            // No CGS symbols (future-macOS insurance): fall back to the
            // material blur rather than a raw see-through window.
            NSLog("Atelier: CGS window blur unavailable; falling back to NSVisualEffectView")
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(blur, positioned: .below, relativeTo: nil)
            NSLayoutConstraint.activate([
                blur.topAnchor.constraint(equalTo: container.topAnchor),
                blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        buildChrome(in: container)
        observeFocus(of: window)
    }

    // MARK: Focus articulation (POLISH_PLAN Phase 1)

    private func observeFocus(of window: NSWindow) {
        // Every focus change funnels through makeFirstResponder — ours and
        // AppKit's (clicks) — so the subclass hook is the one reliable signal.
        (window as? AtelierWindow)?.onFirstResponderChange = { [weak self] in
            self?.refreshFocusArticulation()
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowKeyDidChange),
                           name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: #selector(windowKeyDidChange),
                           name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowKeyDidChange() {
        refreshFocusArticulation()
    }

    /// Re-aim the hairline and caret truth at the current first responder.
    private func refreshFocusArticulation() {
        guard let window, let session = activeSession else { return }
        session.updateFocusArticulation(firstResponder: window.firstResponder, windowIsKey: window.isKeyWindow)
        session.syncCaretFocus(firstResponder: window.firstResponder, windowIsKey: window.isKeyWindow)
    }

    /// Snapshot for the session store.
    func persisted() -> PersistedWindow {
        PersistedWindow(sessions: sessions.map { $0.persisted() }, activeIndex: activeIndex)
    }

    /// Dev-only (snapshot debug dump): the active session's shell wash
    /// geometry plus every translucent-painting view in the window, for
    /// reconciling snapshot alpha probes with the live tree.
    var debugWashState: String {
        var lines = [activeSession.map { "\(window?.title ?? "?"): \($0.shellPane.debugWashState)" } ?? "no session"]
        func walk(_ view: NSView, depth: Int) {
            let bg = view.layer?.backgroundColor
            let alpha = bg?.alpha ?? 0
            if alpha > 0, let root = window?.contentView {
                let frame = view.convert(view.bounds, to: root)
                let comps = bg?.components?.map { String(format: "%.2f", $0) }.joined(separator: ",") ?? "?"
                lines.append("\(String(repeating: "  ", count: depth))\(type(of: view)) frame=\(frame) bg=(\(comps)) hidden=\(view.isHiddenOrHasHiddenAncestor)")
            }
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        if let root = window?.contentView { walk(root, depth: 0) }
        return lines.joined(separator: "\n")
    }

    deinit {
        titleTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func buildChrome(in container: NSView) {
        sessionArea.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.delegate = self
        container.addSubview(sessionArea)
        container.addSubview(bottomBar)

        // Pin below the titlebar/tab bar, not the window top: with
        // .fullSizeContentView the contentView extends under the chrome, and the
        // panes would draw straight through the project tab strip.
        let contentTop = (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? container.topAnchor

        // §3.1: the titlebar/tab-strip region gets the same mantle-over-blur
        // wash as the bottom bar — one material language from the top edge
        // down. The native tab chrome draws above this, on our material.
        let titlebarWash = TitlebarWashView()
        titlebarWash.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titlebarWash)
        NSLayoutConstraint.activate([
            titlebarWash.topAnchor.constraint(equalTo: container.topAnchor),
            titlebarWash.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titlebarWash.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titlebarWash.bottomAnchor.constraint(equalTo: contentTop),
        ])

        NSLayoutConstraint.activate([
            sessionArea.topAnchor.constraint(equalTo: contentTop),
            sessionArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sessionArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            // The bar's frame includes the folder labels' overhang band; the
            // panes run under that band (it's transparent and pass-through).
            sessionArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: BottomBar.overhang),

            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let height = bottomBar.heightAnchor.constraint(equalToConstant: BottomBar.rowHeight + BottomBar.overhang)
        height.isActive = true
        bottomBarHeight = height
        bottomBar.onDesiredHeightChange = { [weak self] newHeight in
            self?.bottomBarHeight?.constant = newHeight + BottomBar.overhang
        }
        // After an inline tab rename ends (commit or cancel), typing belongs
        // to the session again — but only when focus fell into limbo (↩/Esc
        // leave it on the window). A click-away commit already put focus
        // exactly where the user aimed; don't second-guess it.
        bottomBar.onRenameDidEnd = { [weak self] in
            guard let self, let window = self.window else { return }
            if window.firstResponder == nil || window.firstResponder === window {
                window.makeFirstResponder(self.activeSession?.defaultFocusView)
            }
        }
    }

    /// Start the hosted processes for every session. Called once the window is on
    /// screen (deferred so terminals get a real size first).
    func startProcesses() {
        processesStarted = true
        for session in sessions { session.start() }
        window?.makeFirstResponder(activeSession?.defaultFocusView)
        startTitleTimer()
    }

    // MARK: Sessions

    /// `⌘T` — a new Landing tab (a terminal, promotable to an IDE).
    func addSession() {
        adopt(Session(cwd: Self.defaultWorkdir()))
    }

    /// Another session on the project's *main* checkout, no question asked
    /// (the chooser's default answer). A remote session's sibling is another
    /// session on the same host and dir. Falls back to a Landing when the
    /// window isn't anchored to a project yet.
    func addSessionOnMain() {
        if let session = activeSession, case .remote(let host) = session.location {
            adopt(Session(remoteHost: host, remoteDir: session.cwd))
        } else if let root = projectRepoRoot {
            adopt(Session(ideRoot: root))
        } else {
            addSession()
        }
    }

    /// A Landing picked a remote target: replace it, same tab slot, with a
    /// fresh remote session (promotion-in-place can't cross machines — the
    /// landing shell's PTY is local).
    private func replaceLanding(_ landing: Session, withRemote host: String, dir: String) {
        guard let index = sessions.firstIndex(where: { $0 === landing }) else { return }
        RecentsStore.record(RemoteTarget(host: host, dir: dir).id)
        landing.terminate()
        landing.container.removeFromSuperview()
        sessions.remove(at: index)
        adopt(Session(remoteHost: host, remoteDir: dir), at: index)
    }

    private func adopt(_ session: Session, at index: Int? = nil) {
        session.onRemoteRequested = { [weak self, weak session] host, dir in
            guard let self, let session else { return }
            self.replaceLanding(session, withRemote: host, dir: dir)
        }
        session.onPromoted = { [weak self, weak session] in
            guard let self else { return }
            if let session {
                self.noteProjectRoot(for: session)
                if session === self.activeSession {
                    self.window?.makeFirstResponder(session.defaultFocusView)
                }
            }
            self.updateBottomBar()
        }
        let insertAt = min(index ?? sessions.count, sessions.count)
        sessions.insert(session, at: insertAt)
        if processesStarted { session.start() }
        noteProjectRoot(for: session)
        showSession(at: insertAt)
        updateBottomBar()
    }

    /// Anchor the window to its project once the first IDE session exists: cache
    /// the primary checkout and name the native tab after it.
    private func noteProjectRoot(for session: Session) {
        // A remote dir is not a local repo root — anchoring the window to it
        // would aim ⌥⌘T and the worktree chooser at a path that isn't here.
        guard session.state == .ide, !session.isRemote else {
            refreshWindowTitle()
            return
        }
        if projectRepoRoot == nil {
            projectRepoRoot = WorktreeManager.repoRoot(for: session.cwd) ?? session.cwd
            refreshMainBranch()
        }
        refreshWindowTitle()
    }

    /// `repo — branch` (§4): Mission Control thumbnails legible at a glance.
    /// The branch appears when the active session lives on a worktree; the
    /// worktree directory is named for its branch (slashes dashed), which
    /// keeps this off the subprocess path.
    private func refreshWindowTitle() {
        if let session = activeSession, case .remote(let host) = session.location {
            window?.title = session.cwd == "~"
                ? host
                : "\(host) — \((session.cwd as NSString).lastPathComponent)"
            return
        }
        guard let root = projectRepoRoot else {
            window?.title = "New Tab"
            return
        }
        let repo = (root as NSString).lastPathComponent
        if let session = activeSession, session.isWorktree {
            window?.title = "\(repo) — \((session.cwd as NSString).lastPathComponent)"
        } else {
            window?.title = repo
        }
    }

    /// Kill every session's hosted processes (window closing / app quitting) —
    /// including closed-but-alive ones still in their reopen grace window.
    ///
    /// `killRemote: false` (the quit path) leaves remote sessions' tmux'd work
    /// running on their hosts for relaunch to reattach to. Sessions in the
    /// reopen grace were already deliberately closed, so they always kill.
    func terminateAllSessions(killRemote: Bool = true) {
        for session in sessions { session.terminate(killRemote: killRemote) }
        for entry in recentlyClosed { evict(entry: entry) }
        recentlyClosed.removeAll()
    }

    /// `⌘↩` — promote the active Landing to an IDE session rooted at the landing
    /// terminal's current directory (so `cd somewhere` + ⌘↩ = `ide .`).
    func promoteActiveSessionHere() {
        guard let session = activeSession, session.state == .landing else { return }
        let root = session.shellPane.hostedPid.flatMap(ProcessCwd.cwd(of:)) ?? session.cwd
        session.promote(to: root)
    }

    /// `⌘W`. A dirty editor buffer gets the informative refusal first (§5):
    /// the file is named, the loss is stated, saving is one button away.
    func closeActiveSession() {
        guard let session = activeSession else { return }
        guardDirtyBuffer(
            in: session,
            saveButton: "Save and Close",
            informative: "Closing this session will discard them."
        ) { [weak self] in
            self?.forceCloseActiveSession()
        }
    }

    /// Run `proceed` now if the session's buffer is clean; otherwise the
    /// informative refusal — the file named, the loss stated, save one
    /// button away.
    private func guardDirtyBuffer(
        in session: Session,
        saveButton: String,
        informative: String,
        then proceed: @escaping () -> Void
    ) {
        guard session.editorPane.isDirty, let path = session.editorPane.filePath, let window else {
            proceed()
            return
        }
        let alert = NSAlert()
        alert.messageText = "\((path as NSString).lastPathComponent) has unsaved changes"
        alert.informativeText = informative
        alert.addButton(withTitle: saveButton)
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                do {
                    try session.editorPane.save()
                    proceed()
                } catch {
                    self?.presentError(title: "Couldn't save \((path as NSString).lastPathComponent)", error: error)
                }
            case .alertSecondButtonReturn:
                proceed()
            default:
                break
            }
        }
    }

    private func forceCloseActiveSession() {
        guard sessions.indices.contains(activeIndex) else { return }
        let session = sessions.remove(at: activeIndex)
        // Only promoted sessions are worth resurrecting — a Landing is just a
        // shell and dies now. IDE sessions go into the grace window alive.
        if session.state == .ide {
            recentlyClosed.append(.live(session, index: activeIndex))
            if recentlyClosed.count > 10 { evict(entry: recentlyClosed.removeFirst()) }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeGrace) { [weak self, weak session] in
                guard let self, let session else { return }
                self.expireGrace(for: session)
            }
        } else {
            session.terminate()
        }
        session.container.removeFromSuperview()

        if sessions.isEmpty {
            // Closing the last tab kicks back to the Launch view — the window
            // un-anchors from its project and becomes a fresh Landing.
            revertToLanding()
            return
        }
        showSession(at: min(activeIndex, sessions.count - 1))
        updateBottomBar()
    }

    private func revertToLanding() {
        projectRepoRoot = nil
        window?.title = "New Tab"
        addSession()
        landingFromRevert = sessions.last
    }

    /// `⌘⇧T` — bring back the most recently closed session whose root still
    /// exists (a root can vanish under the stack: worktree removed). Inside
    /// the grace window the exact live session returns; past it the agent
    /// resumes the same conversation from disk. Old position either way.
    func reopenClosedSession() {
        while let entry = recentlyClosed.popLast() {
            let (cwd, index) = entryLocation(entry)
            // Remote roots aren't stat-able here; reopen optimistically (the
            // reconnecting placard covers a host that's gone).
            var isDir: ObjCBool = false
            guard entryIsRemote(entry)
                || (FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir) && isDir.boolValue) else {
                evict(entry: entry)
                continue
            }
            if let auto = landingFromRevert, sessions.count == 1, sessions[0] === auto,
               auto.state == .landing {
                auto.terminate()
                auto.container.removeFromSuperview()
                sessions.removeAll()
            }
            switch entry {
            case .live(let session, _):
                adopt(session, at: min(index, sessions.count))
            case .snapshot(let persisted, _):
                adopt(Session(restored: persisted), at: min(index, sessions.count))
            }
            return
        }
    }

    var canReopenClosedSession: Bool { !recentlyClosed.isEmpty }

    private func entryLocation(_ entry: ClosedEntry) -> (cwd: String, index: Int) {
        switch entry {
        case .live(let session, let index): return (session.cwd, index)
        case .snapshot(let persisted, let index): return (persisted.cwd, index)
        }
    }

    private func entryIsRemote(_ entry: ClosedEntry) -> Bool {
        switch entry {
        case .live(let session, _): return session.isRemote
        case .snapshot(let persisted, _): return persisted.remoteHost != nil
        }
    }

    /// Grace over: the hidden session's processes die and the entry becomes
    /// a `--resume` snapshot.
    private func expireGrace(for session: Session) {
        guard let slot = recentlyClosed.firstIndex(where: {
            if case .live(let live, _) = $0 { return live === session }
            return false
        }) else { return }
        guard case .live(_, let index) = recentlyClosed[slot] else { return }
        session.terminate()
        recentlyClosed[slot] = .snapshot(session.persisted(), index: index)
    }

    private func evict(entry: ClosedEntry) {
        if case .live(let session, _) = entry { session.terminate() }
    }

    /// Hidden-but-alive closed sessions on `path` (worktree removal must not
    /// leave PTYs holding a tree that's being deleted).
    func purgeClosedSessions(under path: String) {
        recentlyClosed.removeAll { entry in
            if case .live(let session, _) = entry, session.cwd == path {
                session.terminate()
                return true
            }
            if case .snapshot(let persisted, _) = entry, persisted.cwd == path {
                return true
            }
            return false
        }
    }

    // MARK: Editor (M2.1)

    var canUseEditor: Bool {
        guard let session = activeSession else { return false }
        return session.state == .ide && !session.isRemote
    }
    var editorHasFile: Bool { activeSession?.editorPane.filePath != nil }

    /// Buffers with unsaved edits across this window's sessions — the app's
    /// quit guard names them (§5: the refusal names the actual loss).
    var dirtyBufferPaths: [String] {
        sessions.compactMap { $0.editorPane.isDirty ? $0.editorPane.filePath : nil }
    }

    /// Save every dirty buffer; throws on the first failure.
    func saveAllDirtyBuffers() throws {
        for session in sessions where session.editorPane.isDirty {
            try session.editorPane.save()
        }
    }

    /// `⌘O` — open a file into the editor pane. The panel roots at the
    /// session's cwd; Split mode flips back to the Triptych so the buffer is
    /// actually on screen. (`⌘P`'s summon picker replaces this as the fast
    /// path in M2.2; the panel stays as the native fallback.)
    func openFileInEditor() {
        guard let session = activeSession, session.state == .ide, let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: session.cwd)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.openInEditor(url: url, session: session)
        }
    }

    /// The one buffer is precious (M2.1): opening over unsaved edits gets the
    /// same refusal closing does. `cursor` lands a search hit (M2.3).
    private func openInEditor(url: URL, session: Session, cursor: (line: Int, column: Int)? = nil) {
        guardDirtyBuffer(
            in: session,
            saveButton: "Save and Open",
            informative: "Opening \(url.lastPathComponent) will discard them."
        ) { [weak self] in
            guard let self else { return }
            do {
                session.editorPane.lspRoot = session.cwd
                try session.editorPane.open(path: url.path)
                if let cursor {
                    session.editorPane.reveal(line: cursor.line, column: cursor.column)
                }
                if session === self.activeSession {
                    if session.layoutMode == .split { self.toggleLayout() }
                    self.window?.makeFirstResponder(session.editorPane.focusView)
                }
            } catch {
                self.presentError(title: "Couldn't open \(url.lastPathComponent)", error: error)
            }
        }
    }

    // MARK: File picker (M2.2 — the ⌘P summon)

    private var filePicker: FilePicker?

    func showFilePicker() {
        guard filePicker == nil, palette == nil, repoSearch == nil,
              let session = activeSession, session.state == .ide,
              let container = window?.contentView else { return }

        let overlay = FilePicker(
            root: session.cwd,
            onDismiss: { [weak self] in self?.dismissFilePicker() },
            onOpen: { [weak self] url in self?.openInEditor(url: url, session: session) }
        )
        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlay)
        let contentTop = (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? container.topAnchor
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: contentTop),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        filePicker = overlay
        captureFocusForOverlay()
        window?.makeFirstResponder(overlay.focusField)
        overlay.animateIn()
    }

    private func dismissFilePicker() {
        filePicker?.removeFromSuperview()
        filePicker = nil
        restorePreOverlayFocus()
    }

    // MARK: Repo search (M2.3 — the ⌘⇧F summon)

    private var repoSearch: RepoSearchOverlay?

    func showRepoSearch() {
        guard repoSearch == nil, palette == nil, filePicker == nil,
              let session = activeSession, session.state == .ide,
              let container = window?.contentView else { return }

        let overlay = RepoSearchOverlay(
            root: session.cwd,
            onDismiss: { [weak self] in self?.dismissRepoSearch() },
            onOpen: { [weak self] url, line, column in
                self?.openInEditor(url: url, session: session, cursor: (line, column))
            }
        )
        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlay)
        let contentTop = (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? container.topAnchor
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: contentTop),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        repoSearch = overlay
        captureFocusForOverlay()
        window?.makeFirstResponder(overlay.focusField)
        overlay.animateIn()
    }

    private func dismissRepoSearch() {
        repoSearch?.removeFromSuperview()
        repoSearch = nil
        restorePreOverlayFocus()
    }

    /// `⌘S` — write the buffer back to its file.
    func saveEditor() {
        guard let session = activeSession, session.editorPane.filePath != nil else { return }
        do {
            try session.editorPane.save()
        } catch {
            presentError(title: "Couldn't save", error: error)
        }
    }

    /// Dev-only (lspProbe debug): definition at a given 1-based position in
    /// the active buffer plus the last published diagnostics, as text.
    func lspProbe(line: Int, column: Int, completion: @escaping (String) -> Void) {
        guard let session = activeSession, session.state == .ide,
              let path = session.editorPane.filePath,
              let client = LSPRegistry.client(for: session.cwd) else {
            completion("lspProbe: no active editor buffer or no language server")
            return
        }
        let diagnostics = session.editorPane.lastDiagnostics
        client.definition(path: path, line: line - 1, character: column - 1) { targets in
            var dump = "definition @\(line):\(column) in \(path):\n"
            dump += targets.isEmpty
                ? "  (no result)\n"
                : targets.map { "  \($0.path):\($0.line):\($0.column)" }.joined(separator: "\n") + "\n"
            dump += "diagnostics (\(diagnostics.count)):\n"
            dump += diagnostics.prefix(10).map {
                "  \($0.startLine + 1):\($0.startCharacter + 1) [\($0.severity)] \($0.message)"
            }.joined(separator: "\n")
            completion(dump)
        }
    }

    /// F12 — go to definition at the caret (M2.5). Same-file jumps reveal in
    /// place; cross-file jumps ride the ⌘P open path (dirty guard included).
    /// No result is a quiet no-op: the server may still be indexing, and a
    /// missing definition isn't an error worth a dialog.
    func goToDefinition() {
        guard let session = activeSession, session.state == .ide,
              let path = session.editorPane.filePath,
              let cursor = session.editorPane.cursorPosition,
              let client = LSPRegistry.client(for: session.cwd)
        else { return }
        client.definition(path: path, line: cursor.line - 1, character: cursor.column - 1) { [weak self] targets in
            guard let self, let target = targets.first else { return }
            if target.path == path {
                session.editorPane.reveal(line: target.line, column: target.column)
                self.window?.makeFirstResponder(session.editorPane.focusView)
            } else {
                self.openInEditor(
                    url: URL(fileURLWithPath: target.path),
                    session: session,
                    cursor: (target.line, target.column)
                )
            }
        }
    }

    func selectNext() { guard !sessions.isEmpty else { return }; showSession(at: (activeIndex + 1) % sessions.count) }
    func selectPrev() { guard !sessions.isEmpty else { return }; showSession(at: (activeIndex - 1 + sessions.count) % sessions.count) }

    private func showSession(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        activeSession?.container.removeFromSuperview()
        activeIndex = index
        let session = sessions[index]
        // Focusing a tab is "seeing" it: an unseen completion becomes *waiting* —
        // the agent finished and it's your move (§7.1). Live states stay as-is.
        if session.attention == .doneUnseen { session.attention = .waiting }

        session.container.removeFromSuperview()
        sessionArea.addSubview(session.container)
        NSLayoutConstraint.activate([
            session.container.topAnchor.constraint(equalTo: sessionArea.topAnchor),
            session.container.bottomAnchor.constraint(equalTo: sessionArea.bottomAnchor),
            session.container.leadingAnchor.constraint(equalTo: sessionArea.leadingAnchor),
            session.container.trailingAnchor.constraint(equalTo: sessionArea.trailingAnchor),
        ])
        session.refreshLanding()
        window?.makeFirstResponder(session.defaultFocusView)
        refreshWindowTitle()
        updateBottomBar()
    }

    /// Sessions whose state means "your move is the bottleneck" — unseen
    /// completions and explicit blocks. Feeds the Dock badge (§4); plain
    /// peach waiting and working deliberately don't count.
    var actionableSessionCount: Int {
        sessions.filter { $0.attention == .doneUnseen || $0.attention == .needsInput }.count
    }

    // MARK: Layout & focus

    func toggleLayout() {
        activeSession?.toggleLayout()
        updateBottomBar()
        // The first responder usually survives the toggle, so the KVO won't
        // fire — re-lay the hairline against the new pane tree explicitly.
        refreshFocusArticulation()
    }

    func focusPane(_ direction: FocusDirection) {
        guard let session = activeSession, let window else { return }
        let panes = session.visiblePanes
        guard !panes.isEmpty else { return }

        let current = panes.first { pane in
            guard let fr = window.firstResponder as? NSView else { return false }
            return fr === pane.focusView || fr.isDescendant(of: pane)
        } ?? panes[0]

        let curFrame = current.convert(current.bounds, to: nil)
        let curCenter = CGPoint(x: curFrame.midX, y: curFrame.midY)

        var best: WorkspacePane?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for pane in panes where pane !== current {
            let frame = pane.convert(pane.bounds, to: nil)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let inDirection: Bool
            switch direction {
            case .left:  inDirection = center.x < curCenter.x - 1
            case .right: inDirection = center.x > curCenter.x + 1
            case .up:    inDirection = center.y > curCenter.y + 1 // AppKit y grows upward
            case .down:  inDirection = center.y < curCenter.y - 1
            }
            guard inDirection else { continue }
            let distance = hypot(center.x - curCenter.x, center.y - curCenter.y)
            if distance < bestDistance { bestDistance = distance; best = pane }
        }
        if let best {
            window.makeFirstResponder(best.focusView)
            // A directional jump earns the ~150 ms glow-then-settle (§3); the
            // KVO has already re-laid the hairline by the time we get here.
            activeSession?.glowFocus()
        }
    }

    // MARK: Bottom bar

    private func updateBottomBar() {
        // A fresh window — one unpromoted Landing — shows no bar: there's no repo
        // yet and nothing to switch. The bar appears with promotion or a second tab.
        let barHidden = sessions.count == 1 && sessions[0].state == .landing
        bottomBar.isHidden = barHidden
        bottomBarHeight?.constant = barHidden ? 0 : bottomBar.desiredHeight + BottomBar.overhang

        // The pill is *static* per window: the project name once anchored, so
        // switching sessions never reflows the bar. Pre-anchor it shows where a
        // landing would open.
        let pill: String
        if let projectRepoRoot {
            pill = (projectRepoRoot as NSString).lastPathComponent
        } else if let session = activeSession {
            pill = Self.abbreviate(session.cwd)
        } else {
            pill = ""
        }
        let mode: LayoutMode? = activeSession?.state == .ide ? activeSession?.layoutMode : nil
        bottomBar.update(
            tabs: groupedTabs(),
            activeIndex: activeIndex,
            pill: pill,
            mode: mode
        )
        // Every attention change passes through here — the Dock badge rides along.
        (NSApp.delegate as? AppDelegate)?.refreshDockBadge()
    }

    /// Display order for the strip: tabs grouped by root, groups in
    /// first-appearance order — which is the sessions' array order, so a
    /// dragged arrangement (tabs within a folder, folders past each other)
    /// is exactly what persists (MILESTONE_1 §7).
    private func groupedTabs() -> [SessionTabInfo] {
        var groupOrder: [String] = []
        var groups: [String: [Int]] = [:]
        for (index, session) in sessions.enumerated() {
            // Remote sessions group by host — every jarvis tab sits together
            // regardless of remote dir, like worktree tabs share their root.
            let key = session.location.host.map { "ssh://\($0)" } ?? session.cwd
            if groups[key] == nil {
                groups[key] = []
                groupOrder.append(key)
            }
            groups[key]?.append(index)
        }
        return groupOrder.flatMap { key in
            (groups[key] ?? []).map { index in
                let session = sessions[index]
                return SessionTabInfo(
                    id: session.id,
                    index: index,
                    title: session.displayTitle,
                    isWorktree: session.isWorktree,
                    remoteHost: session.location.host,
                    groupKey: key,
                    groupLabel: folderLabel(for: session, key: key),
                    attention: session.attention,
                    attentionSince: session.attentionSince
                )
            }
        }
    }

    /// What a group's folder tab says: the *worktree*, never the branch — the
    /// repo name for the main checkout, `⎇ dir` for a linked worktree, `@host`
    /// for a remote group. Folders are places; the branch checked out in one
    /// is a state, revealed on hover (owner call 2026-09-07).
    private func folderLabel(for session: Session, key: String) -> String {
        if let host = session.location.host { return "@\(host)" }
        if session.isWorktree { return "⎇ \((session.cwd as NSString).lastPathComponent)" }
        return (session.cwd as NSString).lastPathComponent
    }

    // MARK: Attention (MILESTONE_1 §7.1)

    /// Apply an agent hook event to the session that fired it. Returns false if
    /// the session lives in another window. The dot is the agent's exact state:
    /// working and waiting are live facts shown on every tab; a completion you
    /// watched happen goes straight to *waiting* (your move), while one you
    /// missed shows green until seen.
    @discardableResult
    func applyAgentEvent(_ message: NotifyMessage) -> Bool {
        guard let sessionId = message.sessionId,
              let index = sessions.firstIndex(where: { $0.claudeSessionId == sessionId }) else {
            return false
        }
        let onScreen = index == activeIndex && (window?.isKeyWindow ?? false)
        switch message.kind {
        case .working:
            sessions[index].attention = .working
        case .blocked:
            // Structured at the source: the hook's `permission_prompt` matcher
            // fired. This is the `!`.
            sessions[index].attention = .needsInput
        case .inputNeeded:
            // `idle_prompt`-matched hooks send this for "your move". Legacy
            // unmatched Notification hooks also land here carrying blockers —
            // for those, fall back to classifying by the message body.
            sessions[index].attention = message.body.lowercased().contains("waiting")
                ? .waiting
                : .needsInput
        case .stop:
            sessions[index].attention = onScreen ? .waiting : .doneUnseen
        }
        updateBottomBar()
        return true
    }

    /// Notification click-to-focus: bring this window forward on the right tab.
    @discardableResult
    func focusSession(claudeSessionId: String) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.claudeSessionId == claudeSessionId }) else {
            return false
        }
        window?.makeKeyAndOrderFront(nil)
        showSession(at: index)
        return true
    }

    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func startTitleTimer() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.refreshTitles() }
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
        refreshTitles()
    }

    /// Re-read each session's title from its transcript; rebuild tabs if any changed.
    /// Remote sessions keep their seeded title — their transcript lives on the
    /// remote host, not under the local `~/.claude/projects/`. (Reading the
    /// ai-title over the shared ssh link is a possible follow-up.)
    private func refreshTitles() {
        var changed = false
        for session in sessions where !session.isRemote {
            let seed = (session.cwd as NSString).lastPathComponent
            let resolved = TranscriptTitle.title(sessionId: session.claudeSessionId, cwd: session.cwd) ?? seed
            if session.title != resolved {
                session.title = resolved
                changed = true
            }
        }
        if changed { updateBottomBar() }
    }

    // MARK: BottomBarDelegate

    func bottomBarDidSelectSession(at index: Int) { showSession(at: index) }
    func bottomBarDidRequestNewSession() { requestNewSession() }
    func bottomBarDidRequestCloseSession(at index: Int) {
        showSession(at: index)
        closeActiveSession()
    }
    func bottomBarDidToggleLayout() { toggleLayout() }
    func bottomBarDidRequestRemoveWorktree(at path: String) { removeWorktree(atPath: path) }
    func bottomBarDidRequestSettings() { SettingsWindowController.shared.show() }

    /// A tab drag ended: adopt the strip's order as the sessions' order. The
    /// array order is what persists, so the arrangement survives relaunch.
    func bottomBarDidReorderSessions(order: [UUID]) {
        let activeId = activeSession?.id
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        sessions = sessions.enumerated().sorted { a, b in
            (rank[a.element.id] ?? order.count + a.offset) < (rank[b.element.id] ?? order.count + b.offset)
        }.map(\.element)
        if let activeId, let index = sessions.firstIndex(where: { $0.id == activeId }) {
            activeIndex = index
        }
        updateBottomBar()
    }

    /// Inline rename committed on a tab: set a custom name that the live
    /// Claude title never overwrites; nil (empty input) reverts to auto.
    func bottomBarDidRenameSession(at index: Int, title: String?) {
        guard sessions.indices.contains(index) else { return }
        sessions[index].customTitle = title
        updateBottomBar()
    }

    /// The palette's "Session: Rename…": same in-place edit the double-click does.
    func renameSession(at index: Int) {
        bottomBar.beginRename(at: index)
    }

    // MARK: Worktree chooser (MILESTONE_1 §6, revised 2026-09-03)

    private var chooserOverlay: WorktreeChooserOverlay?

    /// The main checkout's branch, worn by its folder tab. Cached: the strip
    /// redraws on every attention change and must not shell out to git.
    private var mainBranchName: String?

    private func refreshMainBranch() {
        guard let root = projectRepoRoot else { return }
        mainBranchName = WorktreeManager.currentBranch(root) ?? mainBranchName ?? "main"
    }

    /// Whatever had focus when an overlay stole it. Dismissal puts it back —
    /// falling to the session default only if that view has left the window.
    /// (On a landing the default is now the filter field, which must not
    /// swallow keystrokes meant for the shell the user was just in.)
    private weak var preOverlayFocus: NSView?

    private func captureFocusForOverlay() {
        preOverlayFocus = window?.firstResponder as? NSView
    }

    private func restorePreOverlayFocus() {
        if let view = preOverlayFocus, view.window === window {
            window?.makeFirstResponder(view)
        } else {
            window?.makeFirstResponder(activeSession?.defaultFocusView)
        }
        preOverlayFocus = nil
    }

    /// The `+` / `⌥⌘T`: a new session — after one question, which worktree,
    /// when worktrees are enabled in Settings. Defaults to the main checkout
    /// so the fast path is plus-enter. Worktrees off: straight onto main. A
    /// remote session's sibling is another session on the same host and dir
    /// (no worktrees across the wire); an unanchored window gets a Landing.
    func requestNewSession() {
        if let session = activeSession, case .remote = session.location {
            addSessionOnMain()
        } else if projectRepoRoot != nil, Settings.worktreesEnabled {
            showWorktreeChooser()
        } else {
            addSessionOnMain()
        }
    }

    func showWorktreeChooser(prefill: String? = nil) {
        guard chooserOverlay == nil, palette == nil, filePicker == nil, repoSearch == nil,
              let container = window?.contentView else { return }
        guard let repoRoot = projectRepoRoot
                ?? activeSession.flatMap({ WorktreeManager.repoRoot(for: $0.cwd) }) else {
            NSSound.beep() // landing on a non-repo: nothing to choose from
            return
        }
        let worktrees = WorktreeManager.list(repoRoot: repoRoot)
        guard !worktrees.isEmpty else {
            NSSound.beep()
            return
        }
        if let primary = worktrees.first(where: { $0.isPrimary }) {
            mainBranchName = primary.branch == "(detached)" ? (mainBranchName ?? "main") : primary.branch
        }

        let overlay = WorktreeChooserOverlay(worktrees: worktrees, prefill: prefill) { [weak self] in
            self?.dismissChooser()
        }
        overlay.onStart = { [weak self] worktree in
            self?.dismissChooser()
            self?.adopt(Session(ideRoot: worktree.path))
        }
        overlay.onCreate = { [weak self] branch in
            self?.dismissChooser()
            self?.createWorktree(branch: branch, repoRoot: repoRoot)
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlay)
        let contentTop = (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? container.topAnchor
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: contentTop),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        chooserOverlay = overlay
        captureFocusForOverlay()
        window?.makeFirstResponder(overlay.focusField)
        overlay.animateIn()
    }

    private func dismissChooser() {
        chooserOverlay?.removeFromSuperview()
        chooserOverlay = nil
        restorePreOverlayFocus()
    }

    /// Return-to: focus the worktree's session if one is open, else open one.
    private func openWorktree(at path: String) {
        if let index = sessions.firstIndex(where: { $0.cwd == path }) {
            showSession(at: index)
        } else {
            adopt(Session(ideRoot: path))
        }
    }

    /// CLI entry (`atelier -b <branch>`): open the branch's worktree session,
    /// creating the worktree if needed.
    func openWorktree(branch: String) {
        guard let repoRoot = projectRepoRoot else { return }
        if let existing = WorktreeManager.list(repoRoot: repoRoot).first(where: { $0.branch == branch }) {
            openWorktree(at: existing.path)
        } else {
            createWorktree(branch: branch, repoRoot: repoRoot)
        }
    }

    /// CLI entry (`atelier -rm <branch>`) and the palette: the guarded modal.
    func removeWorktree(branch: String) {
        guard let repoRoot = projectRepoRoot,
              let worktree = WorktreeManager.list(repoRoot: repoRoot).first(where: { $0.branch == branch }),
              !worktree.isPrimary else { return }
        confirmRemoveWorktree(worktree, repoRoot: repoRoot)
    }

    /// The folder tab's context menu: remove the worktree the group sits on.
    func removeWorktree(atPath path: String) {
        guard let repoRoot = projectRepoRoot,
              let worktree = WorktreeManager.list(repoRoot: repoRoot).first(where: { $0.path == path }),
              !worktree.isPrimary else { return }
        confirmRemoveWorktree(worktree, repoRoot: repoRoot)
    }

    /// The worktrees this window's sessions currently sit on, main excluded —
    /// the removable set the palette offers.
    private var openWorktreePaths: [String] {
        var seen: [String] = []
        for session in sessions where session.isWorktree && !seen.contains(session.cwd) {
            seen.append(session.cwd)
        }
        return seen
    }

    private func createWorktree(branch: String, repoRoot: String) {
        do {
            let path = try WorktreeManager.create(branch: branch, repoRoot: repoRoot)
            adopt(Session(ideRoot: path))
        } catch {
            presentError(title: "Couldn't create worktree", error: error)
        }
    }

    /// The informative delete modal: clean → quick confirm; dirty → names the loss
    /// and requires an explicit force (git's own refusal, surfaced).
    private func confirmRemoveWorktree(_ worktree: Worktree, repoRoot: String) {
        let branch = worktree.branch
        let openSessions = sessions.filter { $0.cwd == worktree.path }
        // Re-check the truth at decision time.
        let isDirty = WorktreeManager.isDirty(worktree.path)

        let alert = NSAlert()
        if isDirty {
            alert.alertStyle = .critical
            alert.messageText = "⎇ \(branch) has uncommitted changes"
            alert.informativeText = "Removing this worktree will permanently discard them."
                + (openSessions.isEmpty ? "" : " Its \(openSessions.count) open session(s) will close.")
            // The refusal names the actual loss (§5): the real `git status
            // --short` lines, in mono — not a vague "changes exist".
            let lines = WorktreeManager.statusLines(worktree.path)
            if !lines.isEmpty {
                let shown = lines.prefix(8)
                var text = shown.joined(separator: "\n")
                if lines.count > shown.count { text += "\n… and \(lines.count - shown.count) more" }
                let label = NSTextField(labelWithString: text)
                label.font = Theme.Typography.mono(Theme.Typography.small)
                label.textColor = Theme.chromeText
                label.lineBreakMode = .byTruncatingTail
                label.frame = NSRect(x: 0, y: 0, width: 360, height: label.fittingSize.height)
                alert.accessoryView = label
            }
            alert.addButton(withTitle: "Force Remove")
        } else {
            alert.messageText = "Remove worktree ⎇ \(branch)?"
            alert.informativeText = "The checkout at \(Self.abbreviate(worktree.path)) will be deleted."
                + (openSessions.isEmpty ? "" : " Its \(openSessions.count) open session(s) will close.")
            alert.addButton(withTitle: "Remove")
        }
        alert.addButton(withTitle: "Cancel")

        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do {
                // Close its sessions first so no PTY holds the tree.
                for session in openSessions {
                    if let index = self.sessions.firstIndex(where: { $0 === session }) {
                        self.sessions.remove(at: index)
                        session.terminate()
                        session.container.removeFromSuperview()
                    }
                }
                if self.sessions.isEmpty {
                    self.adopt(Session(ideRoot: repoRoot))
                } else {
                    self.showSession(at: min(self.activeIndex, self.sessions.count - 1))
                    self.updateBottomBar()
                }
                // Closed-but-alive sessions in the reopen grace also hold PTYs
                // on this tree — release them before git deletes it.
                self.purgeClosedSessions(under: worktree.path)
                try WorktreeManager.remove(path: worktree.path, repoRoot: repoRoot, force: isDirty)
            } catch {
                self.presentError(title: "Couldn't remove worktree", error: error)
            }
        }
    }

    // MARK: Command palette (MILESTONE_1 §8)

    private var palette: CommandPalette?

    func showPalette() {
        guard palette == nil, filePicker == nil, repoSearch == nil,
              let container = window?.contentView else { return }

        let overlay = CommandPalette(commands: paletteCommands()) { [weak self] in
            self?.dismissPalette()
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlay)
        let contentTop = (window?.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? container.topAnchor
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: contentTop),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        palette = overlay
        captureFocusForOverlay()
        window?.makeFirstResponder(overlay.focusField)
        overlay.animateIn()
    }

    private func dismissPalette() {
        palette?.removeFromSuperview()
        palette = nil
        restorePreOverlayFocus()
    }

    /// The fixed command set (§8), plus dynamic switch targets. Category-prefixed
    /// so fuzzy search groups (`wt` surfaces every worktree command).
    private func paletteCommands() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []

        if activeSession?.state == .landing {
            commands.append(PaletteCommand(id: "session.ideHere", title: "Session: Open IDE Here", key: "⌘↩") { [weak self] in
                self?.promoteActiveSessionHere()
            })
        }
        commands.append(PaletteCommand(id: "session.new", title: "Session: New…", key: "⌥⌘T") { [weak self] in
            self?.requestNewSession()
        })
        commands.append(PaletteCommand(id: "session.close", title: "Session: Close", key: "⌘W") { [weak self] in
            self?.closeActiveSession()
        })
        if canReopenClosedSession {
            commands.append(PaletteCommand(id: "session.reopen", title: "Session: Reopen Closed", key: "⌘⇧T") { [weak self] in
                self?.reopenClosedSession()
            })
        }
        commands.append(PaletteCommand(id: "session.next", title: "Session: Next", key: "⌘⇧]") { [weak self] in
            self?.selectNext()
        })
        commands.append(PaletteCommand(id: "session.prev", title: "Session: Previous", key: "⌘⇧[") { [weak self] in
            self?.selectPrev()
        })
        commands.append(PaletteCommand(id: "session.rename", title: "Session: Rename…", key: nil) { [weak self] in
            guard let self else { return }
            self.renameSession(at: self.activeIndex)
        })
        for (index, session) in sessions.enumerated() where index != activeIndex {
            commands.append(PaletteCommand(id: "session.switch.\(index)", title: "Session: Switch to \(session.title)", key: nil) { [weak self] in
                self?.showSession(at: index)
            })
        }

        if projectRepoRoot != nil {
            commands.append(PaletteCommand(id: "worktree.new", title: "Worktree: New…", key: nil) { [weak self] in
                self?.showWorktreeChooser(prefill: "")
            })
            for path in openWorktreePaths {
                let name = (path as NSString).lastPathComponent
                commands.append(PaletteCommand(id: "worktree.remove.\(name)", title: "Worktree: Remove ⎇ \(name)…", key: nil) { [weak self] in
                    self?.removeWorktree(atPath: path)
                })
            }
        }

        commands.append(PaletteCommand(id: "project.new", title: "Project: New Tab", key: "⌘T") {
            (NSApp.delegate as? AppDelegate)?.newProject(nil)
        })
        for (title, window) in (NSApp.delegate as? AppDelegate)?.otherProjects(excluding: self) ?? [] {
            commands.append(PaletteCommand(id: "project.switch.\(title)", title: "Project: Switch to \(title)", key: nil) {
                window.makeKeyAndOrderFront(nil)
            })
        }

        if activeSession?.state == .ide {
            commands.append(PaletteCommand(id: "editor.goto", title: "Editor: Go to File…", key: "⌘P") { [weak self] in
                self?.showFilePicker()
            })
            commands.append(PaletteCommand(id: "editor.search", title: "Editor: Find in Repo…", key: "⌘⇧F") { [weak self] in
                self?.showRepoSearch()
            })
            commands.append(PaletteCommand(id: "editor.open", title: "Editor: Open File…", key: "⌘O") { [weak self] in
                self?.openFileInEditor()
            })
            if editorHasFile {
                commands.append(PaletteCommand(id: "editor.save", title: "Editor: Save", key: "⌘S") { [weak self] in
                    self?.saveEditor()
                })
            }
            commands.append(PaletteCommand(id: "view.layout", title: "View: Toggle Layout", key: "⌘\\") { [weak self] in
                self?.toggleLayout()
            })
        }
        if editorHasFile {
            commands.append(PaletteCommand(id: "editor.definition", title: "Editor: Go to Definition", key: "F12") { [weak self] in
                self?.goToDefinition()
            })
        }
        commands.append(PaletteCommand(id: "view.text.bigger", title: "View: Bigger Text", key: "⌘+") {
            Theme.TypeScale.bump(1)
        })
        commands.append(PaletteCommand(id: "view.text.smaller", title: "View: Smaller Text", key: "⌘-") {
            Theme.TypeScale.bump(-1)
        })
        commands.append(PaletteCommand(id: "view.text.reset", title: "View: Reset Text Size", key: "⌘0") {
            Theme.TypeScale.reset()
        })
        let focusTargets: [(String, WorkspacePane?)] = [
            ("Editor", activeSession?.editorPane),
            ("Shell", activeSession?.shellPane),
            ("Agent", activeSession?.agentPane),
        ]
        for (name, pane) in focusTargets {
            guard let pane else { continue }
            commands.append(PaletteCommand(id: "view.focus.\(name)", title: "View: Focus \(name)", key: nil) { [weak self] in
                self?.window?.makeFirstResponder(pane.focusView)
            })
        }

        commands.append(PaletteCommand(id: "app.quit", title: "Atelier: Quit", key: "⌘Q") {
            NSApp.terminate(nil)
        })
        return commands
    }

    private func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: Environment

    /// Where a fresh Landing's terminal opens, pre-promote — every *project*
    /// session carries its own root (picked repo, worktree, CLI path), so this
    /// only seeds the shell you get before choosing. Deliberately *not* `$HOME`
    /// (avoids Claude enumerating `~/Desktop`/`~/Documents`/`~/Downloads` on
    /// startup): the repos folder is where `cd foo && ⌘↩` starts, and
    /// `ATELIER_WORKDIR` overrides for machines shaped differently.
    private static func defaultWorkdir() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        if let override = ProcessInfo.processInfo.environment["ATELIER_WORKDIR"],
           fm.fileExists(atPath: override) {
            return override
        }
        var isDir: ObjCBool = false
        let repos = "\(home)/repositories"
        if fm.fileExists(atPath: repos, isDirectory: &isDir), isDir.boolValue {
            return repos
        }
        return home
    }

}
