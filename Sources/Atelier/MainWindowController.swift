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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
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

/// The single Atelier window. Milestone 1.2 makes it host *sessions*: it owns a list
/// of `Session`s (each an instance of the fixed pane shape), shows one at a time, and
/// carries a bottom bar with a tab strip to switch between them (MILESTONE_1 §2, §7).
///
/// Projects-as-windows and session persistence are later milestones; for now this is
/// one window hosting N sessions on a shared default root.
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
    /// most recent (the agent resumes its conversation via `--resume`).
    /// In-memory by design: the stack dies with the window, like a browser's.
    private var recentlyClosed: [(session: PersistedSession, index: Int)] = []
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
        // §3.1 titlebar unification, rung (b): the native tab strip composites
        // over the window's backing — tint it mantle so the strip sits in the
        // app's material language instead of stock dark-aqua gray. The tabs
        // themselves stay native (MILESTONE_1 §2 is locked).
        window.backgroundColor = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x25/255.0, alpha: 1.0)
        window.titlebarSeparatorStyle = .none
        // Projects are native window tabs (MILESTONE_1 §2): the OS draws the
        // always-visible project strip in the titlebar.
        window.tabbingMode = .preferred

        let blur = NSVisualEffectView()
        blur.material = .sidebar
        blur.blendingMode = .behindWindow
        // Follows key status deliberately (§3 "the window as an object"): the
        // material desaturates when you leave — the window exhales — and
        // sharpens on return. Terminal content itself never dims.
        blur.state = .followsWindowActiveState
        window.contentView = blur
        window.appearance = NSAppearance(named: .darkAqua)

        self.init(window: window)
        window.center()
        window.setFrameAutosaveName("AtelierMainWindow")
        buildChrome(in: blur)
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
            sessionArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let height = bottomBar.heightAnchor.constraint(equalToConstant: BottomBar.rowHeight)
        height.isActive = true
        bottomBarHeight = height
        bottomBar.onDesiredHeightChange = { [weak self] newHeight in
            self?.bottomBarHeight?.constant = newHeight
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

    /// The tab-strip `+` / `⌥⌘T` — another session on the project's *main*
    /// checkout, regardless of which worktree the active tab is on. Falls back to
    /// a Landing when the window isn't anchored to a project yet.
    func addSessionOnMain() {
        if let root = projectRepoRoot {
            adopt(Session(ideRoot: root))
        } else {
            addSession()
        }
    }

    private func adopt(_ session: Session, at index: Int? = nil) {
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
        guard session.state == .ide else { return }
        if projectRepoRoot == nil {
            projectRepoRoot = WorktreeManager.repoRoot(for: session.cwd) ?? session.cwd
        }
        refreshWindowTitle()
    }

    /// `repo — branch` (§4): Mission Control thumbnails legible at a glance.
    /// The branch appears when the active session lives on a worktree; the
    /// worktree directory is named for its branch (slashes dashed), which
    /// keeps this off the subprocess path.
    private func refreshWindowTitle() {
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

    /// Kill every session's hosted processes (window closing / app quitting).
    func terminateAllSessions() {
        for session in sessions { session.terminate() }
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
        // shell. Snapshot before teardown; `⌘⇧T` brings it back.
        if session.state == .ide {
            recentlyClosed.append((session.persisted(), activeIndex))
            if recentlyClosed.count > 10 { recentlyClosed.removeFirst() }
        }
        session.terminate()
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
    /// exists (a root can vanish under the stack: worktree removed). The agent
    /// resumes the same conversation; the tab returns to its old position.
    func reopenClosedSession() {
        while let entry = recentlyClosed.popLast() {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: entry.session.cwd, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            if let auto = landingFromRevert, sessions.count == 1, sessions[0] === auto,
               auto.state == .landing {
                auto.terminate()
                auto.container.removeFromSuperview()
                sessions.removeAll()
            }
            adopt(Session(restored: entry.session), at: min(entry.index, sessions.count))
            return
        }
    }

    var canReopenClosedSession: Bool { !recentlyClosed.isEmpty }

    // MARK: Editor (M2.1)

    var canUseEditor: Bool { activeSession?.state == .ide }
    var editorHasFile: Bool { activeSession?.editorPane.filePath != nil }

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
    /// same refusal closing does.
    private func openInEditor(url: URL, session: Session) {
        guardDirtyBuffer(
            in: session,
            saveButton: "Save and Open",
            informative: "Opening \(url.lastPathComponent) will discard them."
        ) { [weak self] in
            guard let self else { return }
            do {
                try session.editorPane.open(path: url.path)
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
        guard filePicker == nil, palette == nil,
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

    /// `⌘S` — write the buffer back to its file.
    func saveEditor() {
        guard let session = activeSession, session.editorPane.filePath != nil else { return }
        do {
            try session.editorPane.save()
        } catch {
            presentError(title: "Couldn't save", error: error)
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
        bottomBarHeight?.constant = barHidden ? 0 : bottomBar.desiredHeight

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

    /// Display order for the strip: tabs grouped by root, the project's main
    /// checkout first, worktree groups in first-appearance order (MILESTONE_1 §7).
    private func groupedTabs() -> [SessionTabInfo] {
        var groupOrder: [String] = []
        var groups: [String: [Int]] = [:]
        for (index, session) in sessions.enumerated() {
            if groups[session.cwd] == nil {
                groups[session.cwd] = []
                groupOrder.append(session.cwd)
            }
            groups[session.cwd]?.append(index)
        }
        if let root = projectRepoRoot, let mainIndex = groupOrder.firstIndex(of: root), mainIndex != 0 {
            groupOrder.remove(at: mainIndex)
            groupOrder.insert(root, at: 0)
        }
        return groupOrder.flatMap { key in
            (groups[key] ?? []).map { index in
                let session = sessions[index]
                return SessionTabInfo(
                    id: session.id,
                    index: index,
                    title: session.displayTitle,
                    isWorktree: session.isWorktree,
                    groupKey: key,
                    attention: session.attention,
                    attentionSince: session.attentionSince
                )
            }
        }
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
        case .inputNeeded:
            // The Notification hook carries both Claude's idle "waiting for your
            // input" ping and genuine blockers (permission, question). Only the
            // latter earns the `!`.
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
    private func refreshTitles() {
        var changed = false
        for session in sessions {
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
    func bottomBarDidRequestNewSession() { addSessionOnMain() }
    func bottomBarDidRequestCloseSession(at index: Int) {
        showSession(at: index)
        closeActiveSession()
    }
    func bottomBarDidToggleLayout() { toggleLayout() }
    func bottomBarDidClickPill(anchor: NSView) { showWorktreeFan(from: anchor) }

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

    // MARK: Worktree fan (MILESTONE_1 §6, physiology per POLISH_PLAN §6)

    private var fanOverlay: WorktreeFanOverlay?

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

    func showWorktreeFan(from anchor: NSView? = nil, prefill: String? = nil) {
        guard fanOverlay == nil else { return }
        guard let session = activeSession, let container = window?.contentView,
              let repoRoot = WorktreeManager.repoRoot(for: session.cwd) else {
            NSSound.beep() // landing on a non-repo: nothing to fan
            return
        }
        let anchor = anchor ?? bottomBar.pillAnchor

        // The fan opens next frame (§1.5): one fast `git worktree list` now;
        // the per-tree dirty sweep (a subprocess per worktree) lands async.
        let worktrees = WorktreeManager.list(repoRoot: repoRoot)
        let rows = worktrees.map { worktree in
            WorktreeFanRow(
                worktree: worktree,
                isOpen: sessions.contains { $0.cwd == worktree.path },
                isDirty: false
            )
        }

        let fan = WorktreeFanController(rows: rows)
        fan.prefill = prefill
        fan.onOpen = { [weak self] worktree in
            self?.dismissFan()
            self?.openWorktree(at: worktree.path)
        }
        fan.onCreate = { [weak self] branch in
            self?.dismissFan()
            self?.createWorktree(branch: branch, repoRoot: repoRoot)
        }
        fan.onRemove = { [weak self] row in
            self?.dismissFan()
            self?.confirmRemoveWorktree(row, repoRoot: repoRoot)
        }
        fan.onDismiss = { [weak self] in self?.dismissFan() }

        let overlay = WorktreeFanOverlay(controller: fan) { [weak self] in self?.dismissFan() }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        container.layoutSubtreeIfNeeded()
        overlay.present(abovePillFrame: anchor.convert(anchor.bounds, to: container))
        fanOverlay = overlay
        captureFocusForOverlay()
        window?.makeFirstResponder(overlay.focusField)

        DispatchQueue.global(qos: .userInitiated).async { [weak fan] in
            let dirty = Dictionary(uniqueKeysWithValues: worktrees.map {
                ($0.path, WorktreeManager.isDirty($0.path))
            })
            DispatchQueue.main.async { fan?.updateDirty(dirty) }
        }
    }

    private func dismissFan() {
        fanOverlay?.removeFromSuperview()
        fanOverlay = nil
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

    /// CLI entry (`atelier -rm <branch>`): same guarded modal as the fan's ×.
    func removeWorktree(branch: String) {
        guard let repoRoot = projectRepoRoot,
              let worktree = WorktreeManager.list(repoRoot: repoRoot).first(where: { $0.branch == branch }),
              !worktree.isPrimary else { return }
        let row = WorktreeFanRow(
            worktree: worktree,
            isOpen: sessions.contains { $0.cwd == worktree.path },
            isDirty: WorktreeManager.isDirty(worktree.path)
        )
        confirmRemoveWorktree(row, repoRoot: repoRoot)
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
    private func confirmRemoveWorktree(_ row: WorktreeFanRow, repoRoot: String) {
        let branch = row.worktree.branch
        let openSessions = sessions.filter { $0.cwd == row.worktree.path }
        // The fan's dirty marker is an async hint; the *refusal* re-checks the
        // truth at decision time.
        let isDirty = WorktreeManager.isDirty(row.worktree.path)

        let alert = NSAlert()
        if isDirty {
            alert.alertStyle = .critical
            alert.messageText = "⎇ \(branch) has uncommitted changes"
            alert.informativeText = "Removing this worktree will permanently discard them."
                + (openSessions.isEmpty ? "" : " Its \(openSessions.count) open session(s) will close.")
            // The refusal names the actual loss (§5): the real `git status
            // --short` lines, in mono — not a vague "changes exist".
            let lines = WorktreeManager.statusLines(row.worktree.path)
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
            alert.informativeText = "The checkout at \(Self.abbreviate(row.worktree.path)) will be deleted."
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
                try WorktreeManager.remove(path: row.worktree.path, repoRoot: repoRoot, force: isDirty)
            } catch {
                self.presentError(title: "Couldn't remove worktree", error: error)
            }
        }
    }

    // MARK: Command palette (MILESTONE_1 §8)

    private var palette: CommandPalette?

    func showPalette() {
        guard palette == nil, filePicker == nil, let container = window?.contentView else { return }

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
        commands.append(PaletteCommand(id: "session.new", title: "Session: New on Main", key: "⌥⌘T") { [weak self] in
            self?.addSessionOnMain()
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

        commands.append(PaletteCommand(id: "worktree.fan", title: "Worktree: New / Switch / Remove…", key: nil) { [weak self] in
            guard let self else { return }
            self.showWorktreeFan(from: self.bottomBar.pillAnchor)
        })

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

    /// The directory new sessions open in. Deliberately *not* `$HOME` (avoids Claude
    /// enumerating `~/Desktop`/`~/Documents`/`~/Downloads` on startup). M1.4 replaces
    /// this with the selected repo/worktree; `ATELIER_WORKDIR` overrides meanwhile.
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
