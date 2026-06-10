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

    private let sessionArea = NSView()
    private let bottomBar = BottomBar()
    private var bottomBarHeight: NSLayoutConstraint?
    private var cachedBranch: String?
    private var titleTimer: Timer?

    private var activeSession: Session? {
        sessions.indices.contains(activeIndex) ? sessions[activeIndex] : nil
    }

    convenience init() {
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
        addSession()
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
            // The promoted root names the project — shown in the native tab strip.
            if let session { self.window?.title = (session.cwd as NSString).lastPathComponent }
            self.refreshBranch()
            if let session, session === self.activeSession {
                self.window?.makeFirstResponder(session.defaultFocusView)
            }
        }
        sessions.append(session)
        if processesStarted { session.start() }
        showSession(at: sessions.count - 1)
        refreshBranch()
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
