import AppKit

/// The single Atelier window. Milestone 1.1 brings the fixed three-pane shape and
/// the two layout modes (MILESTONE_1 §3):
///
/// - **Triptych** — editor top-left, shell bottom-left, agent right.
/// - **Split** — agent top, shell bottom, full width; editor hidden.
///
/// The three pane views are long-lived; toggling modes re-parents the *same*
/// instances into a freshly built `NSSplitView` tree, so the PTY-backed terminals
/// (and the editor's future state) survive the switch. Sessions, tabs, and the
/// bottom bar arrive in M1.2 — for now this hosts one implicit session.
final class MainWindowController: NSWindowController, NSSplitViewDelegate {
    private let editorPane = EditorPlaceholderView(frame: .zero)
    private let shellPane = TerminalPane()
    private let agentPane = TerminalPane(deguttersCopy: true)

    private(set) var layoutMode: LayoutMode = .triptych

    /// The split views currently on screen, observed for divider persistence.
    private var liveSplits: [LayoutSplitView] = []
    /// The root of the current layout tree, removed when rebuilding.
    private weak var rootView: NSView?
    /// Suppresses divider-save while we programmatically restore positions.
    private var isRestoringLayout = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Atelier"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true

        // Native blur (VISION / §2.9). The visual-effect view sits behind the
        // transparent terminal panes.
        let blur = NSVisualEffectView()
        blur.material = .sidebar
        blur.blendingMode = .behindWindow
        blur.state = .active
        window.contentView = blur
        window.appearance = NSAppearance(named: .darkAqua)

        self.init(window: window)
        window.center()
        window.setFrameAutosaveName("AtelierMainWindow")

        applyLayout(.triptych)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Layout

    /// Cycle to the other layout mode. Wired to `⌘\` via the View menu.
    func toggleLayout() {
        applyLayout(layoutMode.next)
    }

    /// Build (or rebuild) the pane tree for `mode`, re-parenting the persistent
    /// panes so terminal/editor state is preserved across the switch.
    private func applyLayout(_ mode: LayoutMode) {
        layoutMode = mode
        guard let container = window?.contentView else { return }

        tearDownCurrentLayout()

        let root: NSView
        switch mode {
        case .triptych:
            // Left column: editor over shell. Outer: left column beside agent.
            let leftColumn = makeSplit(slot: LayoutSlots.triptychInner, vertical: false, first: editorPane, second: shellPane)
            root = makeSplit(slot: LayoutSlots.triptychOuter, vertical: true, first: leftColumn, second: agentPane)
        case .split:
            // Agent over shell, full width. Editor is left out of the tree (kept
            // alive, just not parented) — that is what makes Split lossless.
            root = makeSplit(slot: LayoutSlots.splitVertical, vertical: false, first: agentPane, second: shellPane)
        }

        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        rootView = root

        restoreDividers(in: container)
        window?.makeFirstResponder(agentPane.terminal)
    }

    private func tearDownCurrentLayout() {
        for split in liveSplits {
            NotificationCenter.default.removeObserver(self, name: NSSplitView.didResizeSubviewsNotification, object: split)
        }
        liveSplits.removeAll()
        // Detach the persistent panes before discarding their containers.
        for pane in [editorPane, shellPane, agentPane] as [NSView] {
            pane.removeFromSuperview()
        }
        rootView?.removeFromSuperview()
        rootView = nil
    }

    private func makeSplit(slot: LayoutSlot, vertical: Bool, first: NSView, second: NSView) -> LayoutSplitView {
        let split = LayoutSplitView()
        split.slot = slot
        split.isVertical = vertical
        split.dividerStyle = .thin
        split.delegate = self
        first.translatesAutoresizingMaskIntoConstraints = false
        second.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(first)
        split.addArrangedSubview(second)
        liveSplits.append(split)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: split
        )
        return split
    }

    /// Restore each live split's divider to its saved fraction. Runs once layout has
    /// a real size; the async pass handles the first frame, where bounds are still
    /// zero immediately after `addSubview`.
    private func restoreDividers(in container: NSView) {
        isRestoringLayout = true
        container.layoutSubtreeIfNeeded()
        for split in liveSplits { applyFraction(to: split) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for split in self.liveSplits { self.applyFraction(to: split) }
            self.isRestoringLayout = false
        }
    }

    private func applyFraction(to split: LayoutSplitView) {
        let total = split.isVertical ? split.bounds.width : split.bounds.height
        guard total > 0 else { return }
        split.setPosition(split.slot.fraction * total, ofDividerAt: 0)
    }

    @objc private func splitViewDidResize(_ note: Notification) {
        guard !isRestoringLayout, let split = note.object as? LayoutSplitView,
              split.arrangedSubviews.count == 2 else { return }
        let total = split.isVertical ? split.bounds.width : split.bounds.height
        guard total > 0 else { return }
        let first = split.arrangedSubviews[0]
        let firstSize = split.isVertical ? first.frame.width : first.frame.height
        split.slot.fraction = max(0.05, min(0.95, firstSize / total))
    }

    // MARK: NSSplitViewDelegate (min sizes per slot)

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard let split = splitView as? LayoutSplitView else { return proposedMinimumPosition }
        return max(proposedMinimumPosition, split.slot.minFirst)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard let split = splitView as? LayoutSplitView else { return proposedMaximumPosition }
        let total = split.isVertical ? split.bounds.width : split.bounds.height
        return min(proposedMaximumPosition, total - split.slot.minSecond)
    }

    // MARK: Processes

    /// Spawn the two hosted processes. Called once the window is on screen.
    func startProcesses() {
        let workdir = Self.defaultWorkdir()

        shellPane.start(executable: "/bin/zsh", args: ["-l"], cwd: workdir)

        let claude = Self.resolveClaudeBinary()
        agentPane.start(executable: claude, args: [], cwd: workdir)
        agentPane.onProcessTerminated = { code in
            NSLog("Atelier: agent process exited (code: \(String(describing: code)))")
        }

        window?.makeFirstResponder(agentPane.terminal)
    }

    /// The directory both panes open in. Deliberately *not* `$HOME`: launching there
    /// makes Claude Code enumerate `~/Desktop`/`~/Documents`/`~/Downloads` on startup,
    /// each a separate macOS privacy gate — the source of the first-launch prompt
    /// storm. Prefer the code root. (Milestone 1.4 replaces this with the selected
    /// repo/worktree; `ATELIER_WORKDIR` overrides in the meantime.)
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

    /// Locate the `claude` binary. Falls back to a login-shell `command -v` if the
    /// known path is absent (e.g. on another machine).
    private static func resolveClaudeBinary() -> String {
        let known = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude"
        if FileManager.default.isExecutableFile(atPath: known) { return known }

        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        try? probe.run()
        probe.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? known : path
    }
}
