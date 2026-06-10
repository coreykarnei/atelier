import AppKit

/// Direction for the `⌃⌘+hjkl` focus manager.
enum FocusDirection { case left, right, up, down }

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
    private var cachedBranch: String?
    private var titleTimer: Timer?

    private var activeSession: Session? {
        sessions.indices.contains(activeIndex) ? sessions[activeIndex] : nil
    }

    /// `root == nil` opens as a Landing (a new project tab); a path opens the
    /// project directly (the CLI's `atelier <path>`).
    convenience init(root: String? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "New Tab"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // Projects are native window tabs (MILESTONE_1 §2): the OS draws the
        // always-visible project strip in the titlebar.
        window.tabbingMode = .preferred

        let blur = NSVisualEffectView()
        blur.material = .sidebar
        blur.blendingMode = .behindWindow
        blur.state = .active
        window.contentView = blur
        window.appearance = NSAppearance(named: .darkAqua)

        self.init(window: window)
        window.center()
        window.setFrameAutosaveName("AtelierMainWindow")

        buildChrome(in: blur)
        if let root {
            adopt(Session(ideRoot: root))
        } else {
            addSession()
        }
    }

    deinit {
        titleTimer?.invalidate()
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

        NSLayoutConstraint.activate([
            sessionArea.topAnchor.constraint(equalTo: contentTop),
            sessionArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sessionArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sessionArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let height = bottomBar.heightAnchor.constraint(equalToConstant: BottomBar.height)
        height.isActive = true
        bottomBarHeight = height
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

    /// The tab-strip `+` — another session on the active session's root
    /// (MILESTONE_1 §6). Falls back to a Landing when the active tab is one.
    func addSessionOnCurrentRoot() {
        if let active = activeSession, active.state == .ide {
            adopt(Session(ideRoot: active.cwd))
        } else {
            addSession()
        }
    }

    private func adopt(_ session: Session) {
        session.onPromoted = { [weak self, weak session] in
            guard let self else { return }
            if let session {
                self.noteProjectRoot(for: session)
                if session === self.activeSession {
                    self.window?.makeFirstResponder(session.defaultFocusView)
                }
            }
            self.refreshBranch()
        }
        sessions.append(session)
        if processesStarted { session.start() }
        noteProjectRoot(for: session)
        showSession(at: sessions.count - 1)
        refreshBranch()
    }

    /// Anchor the window to its project once the first IDE session exists: cache
    /// the primary checkout and name the native tab after it.
    private func noteProjectRoot(for session: Session) {
        guard session.state == .ide else { return }
        if projectRepoRoot == nil {
            projectRepoRoot = WorktreeManager.repoRoot(for: session.cwd) ?? session.cwd
        }
        window?.title = ((projectRepoRoot ?? session.cwd) as NSString).lastPathComponent
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

    func closeActiveSession() {
        guard sessions.indices.contains(activeIndex) else { return }
        let session = sessions.remove(at: activeIndex)
        session.terminate()
        session.container.removeFromSuperview()

        if sessions.isEmpty {
            window?.close()
            return
        }
        showSession(at: min(activeIndex, sessions.count - 1))
        refreshBranch()
    }

    func selectNext() { guard !sessions.isEmpty else { return }; showSession(at: (activeIndex + 1) % sessions.count) }
    func selectPrev() { guard !sessions.isEmpty else { return }; showSession(at: (activeIndex - 1 + sessions.count) % sessions.count) }

    private func showSession(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        activeSession?.container.removeFromSuperview()
        activeIndex = index
        let session = sessions[index]

        session.container.removeFromSuperview()
        sessionArea.addSubview(session.container)
        NSLayoutConstraint.activate([
            session.container.topAnchor.constraint(equalTo: sessionArea.topAnchor),
            session.container.bottomAnchor.constraint(equalTo: sessionArea.bottomAnchor),
            session.container.leadingAnchor.constraint(equalTo: sessionArea.leadingAnchor),
            session.container.trailingAnchor.constraint(equalTo: sessionArea.trailingAnchor),
        ])
        window?.makeFirstResponder(session.defaultFocusView)
        refreshBranch()
    }

    // MARK: Layout & focus

    func toggleLayout() {
        activeSession?.toggleLayout()
        updateBottomBar()
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
        if let best { window.makeFirstResponder(best.focusView) }
    }

    // MARK: Bottom bar

    private func updateBottomBar() {
        // A fresh window — one unpromoted Landing — shows no bar: there's no repo
        // yet and nothing to switch. The bar appears with promotion or a second tab.
        let barHidden = sessions.count == 1 && sessions[0].state == .landing
        bottomBar.isHidden = barHidden
        bottomBarHeight?.constant = barHidden ? 0 : BottomBar.height

        let pill: String
        var mode: LayoutMode?
        if let session = activeSession {
            switch session.state {
            case .ide:
                pill = cachedBranch.map { "⎇ \($0)" } ?? Self.abbreviate(session.cwd)
                mode = session.layoutMode
            case .landing:
                // No branch to show yet — the pill is still "you are here."
                pill = Self.abbreviate(session.cwd)
            }
        } else {
            pill = ""
        }
        bottomBar.update(
            titles: sessions.map(\.title),
            activeIndex: activeIndex,
            pill: pill,
            mode: mode
        )
    }

    private func refreshBranch() {
        cachedBranch = activeSession.flatMap { session in
            session.state == .ide ? Self.currentBranch(cwd: session.cwd) : nil
        }
        updateBottomBar()
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
    func bottomBarDidRequestNewSession() { addSessionOnCurrentRoot() }
    func bottomBarDidRequestCloseSession(at index: Int) {
        showSession(at: index)
        closeActiveSession()
    }
    func bottomBarDidToggleLayout() { toggleLayout() }
    func bottomBarDidClickPill(anchor: NSView) { showWorktreeFan(from: anchor) }

    // MARK: Worktree fan (MILESTONE_1 §6)

    private var fanPopover: NSPopover?

    private func showWorktreeFan(from anchor: NSView) {
        guard let session = activeSession,
              let repoRoot = WorktreeManager.repoRoot(for: session.cwd) else {
            NSSound.beep() // landing on a non-repo: nothing to fan
            return
        }

        let rows = WorktreeManager.list(repoRoot: repoRoot).map { worktree in
            WorktreeFanRow(
                worktree: worktree,
                isOpen: sessions.contains { $0.cwd == worktree.path },
                isDirty: WorktreeManager.isDirty(worktree.path)
            )
        }

        let fan = WorktreeFanController(rows: rows)
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

        let popover = NSPopover()
        popover.contentViewController = fan
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        fanPopover = popover
    }

    private func dismissFan() {
        fanPopover?.close()
        fanPopover = nil
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

        let alert = NSAlert()
        if row.isDirty {
            alert.alertStyle = .critical
            alert.messageText = "⎇ \(branch) has uncommitted changes"
            alert.informativeText = "Removing this worktree will permanently discard them."
                + (openSessions.isEmpty ? "" : " Its \(openSessions.count) open session(s) will close.")
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
                    self.refreshBranch()
                }
                try WorktreeManager.remove(path: row.worktree.path, repoRoot: repoRoot, force: row.isDirty)
            } catch {
                self.presentError(title: "Couldn't remove worktree", error: error)
            }
        }
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

    /// The current git branch of `cwd`, or nil if it isn't a repo / is detached.
    private static func currentBranch(cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return branch.isEmpty || branch == "HEAD" ? nil : branch
    }
}
