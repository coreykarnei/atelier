import AppKit

/// A pane that can take keyboard focus. The window's focus manager (`⌃⌘+hjkl`) moves
/// the first responder between these (MILESTONE_1 §5).
protocol WorkspacePane: NSView {
    /// The view that should become first responder when this pane is focused.
    var focusView: NSView { get }
}

/// One workspace session (MILESTONE_1 §2). A session starts as a **Landing** — a
/// recents list over a plain terminal, no editor, no Claude — and is **promoted** in
/// place into an IDE session rooted at a chosen directory: the shell re-roots, Claude
/// spawns, and the fixed pane shape appears. Promotion is one-way; a Landing that is
/// never promoted is simply a terminal tab.
///
/// A session owns its (long-lived) panes, its layout mode, and its divider positions.
/// The window shows one session's `container` at a time; switching tabs re-parents
/// containers, so background sessions — and their PTYs — keep running.
///
/// Each session pins its own `claudeSessionId` via `claude --session-id`, so its tab
/// title can be read from exactly that transcript even when several sessions share a
/// cwd (MILESTONE_1 §12, risk 1).
final class Session: NSObject, NSSplitViewDelegate {
    enum State { case landing, ide }

    /// Per-tab attention (MILESTONE_1 §7.1) — about sessions you're *not* looking
    /// at. Set from agent hook events; cleared the moment the tab is focused.
    enum Attention {
        case none
        case working      // agent mid-turn
        case needsInput   // agent blocked on a question
        case doneUnseen   // finished while you were elsewhere
    }

    let id = UUID()
    private(set) var state: State = .landing
    private(set) var cwd: String
    /// Lowercased to match Claude's on-disk transcript filename.
    let claudeSessionId: String
    /// True when this session came back from disk — the agent then *resumes* its
    /// previous Claude conversation instead of starting a fresh one.
    private let isRestored: Bool

    let editorPane = EditorPlaceholderView(frame: .zero)
    let shellPane = TerminalPane()
    let agentPane = TerminalPane(deguttersCopy: true)
    private var landingView: LandingView?

    /// The view the window shows for this session; holds the current split tree.
    let container = NSView()

    /// Tab label. Seeded from the cwd; refreshed from the transcript by the window
    /// controller once Claude assigns an `ai-title`.
    var title: String

    /// A user-given name (double-click the tab) — a hard override that the live
    /// transcript title never replaces.
    var customTitle: String?

    /// Current attention badge for this session's tab.
    var attention: Attention = .none

    /// The label the tab actually shows.
    var displayTitle: String { customTitle ?? title }

    /// True when this session's root is a linked worktree (not the primary
    /// checkout) — drives the ⎇ glyph and tab grouping.
    var isWorktree: Bool {
        cwd.hasPrefix(WorktreeManager.base + "/")
    }

    /// Fired after the session is promoted to an IDE session, so the window can
    /// refresh the branch pill, tabs, and focus.
    var onPromoted: (() -> Void)?

    private(set) var layoutMode: LayoutMode = .triptych

    /// Divider fractions keyed by slot id (ids already encode the mode). In-memory
    /// for M1.2; serialized to disk in M1.5.
    private var dividers: [String: CGFloat] = [:]

    private var liveSplits: [LayoutSplitView] = []
    private weak var rootView: NSView?
    private var isRestoringLayout = false
    private var shellStarted = false

    /// A Landing session (`⌘T`): recents list over a terminal, promotable later.
    init(cwd: String) {
        self.cwd = cwd
        self.title = (cwd as NSString).lastPathComponent
        self.claudeSessionId = UUID().uuidString.lowercased()
        self.isRestored = false
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false

        let landing = LandingView(defaultFolder: cwd)
        landing.onOpen = { [weak self] path in self?.promote(to: path) }
        landingView = landing

        rebuildLayout()
    }

    /// A session born as a full IDE on `root` — the tab-strip `+`'s "another session
    /// on the current root" (MILESTONE_1 §6). No Landing stage.
    init(ideRoot: String) {
        self.cwd = ideRoot
        self.title = (ideRoot as NSString).lastPathComponent
        self.state = .ide
        self.claudeSessionId = UUID().uuidString.lowercased()
        self.isRestored = false
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false
        rebuildLayout()
    }

    /// A session restored from disk (MILESTONE_1 §9). IDE sessions come back on
    /// their root with their layout and dividers; the agent resumes its previous
    /// conversation. Landings come back as Landings.
    init(restored: PersistedSession) {
        self.cwd = restored.cwd
        self.title = restored.title
        self.customTitle = restored.customTitle
        self.claudeSessionId = restored.claudeSessionId
        self.isRestored = true
        self.state = restored.isIDE ? .ide : .landing
        self.layoutMode = LayoutMode(rawValue: restored.layoutMode) ?? .triptych
        self.dividers = restored.dividers.mapValues { CGFloat($0) }
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false

        if state == .landing {
            let landing = LandingView(defaultFolder: cwd)
            landing.onOpen = { [weak self] path in self?.promote(to: path) }
            landingView = landing
        }
        rebuildLayout()
    }

    /// Snapshot for the session store.
    func persisted() -> PersistedSession {
        PersistedSession(
            cwd: cwd,
            isIDE: state == .ide,
            layoutMode: layoutMode.rawValue,
            title: title,
            customTitle: customTitle,
            claudeSessionId: claudeSessionId,
            dividers: dividers.mapValues { Double($0) }
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Lifecycle

    /// Spawn the hosted processes: the shell always; Claude only if this is already
    /// an IDE session. For a Landing, Claude spawns on promote, rooted in a real
    /// project — never in a junk default cwd. Idempotent.
    func start() {
        guard !shellStarted else { return }
        shellStarted = true
        shellPane.start(executable: "/bin/zsh", args: ["-l"], cwd: cwd)
        if state == .ide { startAgent() }
    }

    /// Promote this Landing into an IDE session rooted at `root`: re-root the shell,
    /// spawn Claude there, switch to the Triptych. One-way; no-op if already an IDE.
    func promote(to root: String) {
        guard state == .landing else { return }
        state = .ide
        cwd = root
        title = (root as NSString).lastPathComponent
        RecentsStore.record(root)

        // Re-root the live shell — same move the `ide` script makes (send-keys cd).
        shellPane.send(text: " cd '\(root)' && clear\r")
        startAgent()

        rebuildLayout()
        landingView = nil
        onPromoted?()
    }

    private var agentStarted = false

    private func startAgent() {
        guard !agentStarted else { return }
        agentStarted = true
        let claude = Session.resolveClaudeBinary()
        // A restored session resumes its previous conversation — provided its
        // transcript still exists; otherwise start fresh under the same id.
        let args: [String]
        if isRestored, Self.transcriptExists(sessionId: claudeSessionId, cwd: cwd) {
            args = ["--resume", claudeSessionId]
        } else {
            args = ["--session-id", claudeSessionId]
        }
        agentPane.start(executable: claude, args: args, cwd: cwd)
        agentPane.onProcessTerminated = { [id] code in
            NSLog("Atelier: agent process exited (session \(id), code: \(String(describing: code)))")
        }
    }

    private static func transcriptExists(sessionId: String, cwd: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let encoded = cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return FileManager.default.fileExists(
            atPath: "\(home)/.claude/projects/\(encoded)/\(sessionId).jsonl"
        )
    }

    /// Terminate the hosted processes when the session is closed.
    func terminate() {
        shellPane.terminate()
        if agentStarted { agentPane.terminate() }
    }

    // MARK: Focus

    /// The pane that should receive focus when this session is shown. A Landing is
    /// terminal-first: ⌘T gives a usable shell immediately; the list is one ⌃⌘k away.
    var defaultFocusView: NSView {
        state == .ide ? agentPane.terminal : shellPane.terminal
    }

    /// Panes currently on screen, in reading order — editor is absent in Split,
    /// list + shell in a Landing.
    var visiblePanes: [WorkspacePane] {
        switch state {
        case .landing:
            return [landingView, shellPane].compactMap { $0 }
        case .ide:
            switch layoutMode {
            case .triptych: return [editorPane, shellPane, agentPane]
            case .split: return [agentPane, shellPane]
            }
        }
    }

    // MARK: Layout

    /// Toggle Triptych/Split. Meaningless for a Landing, so a no-op there.
    func toggleLayout() {
        guard state == .ide else { return }
        layoutMode = layoutMode.next
        rebuildLayout()
    }

    private func fraction(for slot: LayoutSlot) -> CGFloat {
        dividers[slot.id] ?? slot.defaultFraction
    }

    private func setFraction(_ value: CGFloat, for slot: LayoutSlot) {
        dividers[slot.id] = value
    }

    /// Build (or rebuild) the pane tree for the current state/mode into `container`,
    /// re-parenting the persistent panes so terminal/editor state survives the switch.
    private func rebuildLayout() {
        tearDownCurrentLayout()

        let root: NSView
        switch state {
        case .landing:
            root = makeSplit(slot: LayoutSlots.landingVertical, vertical: false, first: landingView!, second: shellPane)
        case .ide:
            switch layoutMode {
            case .triptych:
                let leftColumn = makeSplit(slot: LayoutSlots.triptychInner, vertical: false, first: editorPane, second: shellPane)
                root = makeSplit(slot: LayoutSlots.triptychOuter, vertical: true, first: leftColumn, second: agentPane)
            case .split:
                root = makeSplit(slot: LayoutSlots.splitVertical, vertical: false, first: agentPane, second: shellPane)
            }
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

        restoreDividers()
    }

    private func tearDownCurrentLayout() {
        for split in liveSplits {
            NotificationCenter.default.removeObserver(self, name: NSSplitView.didResizeSubviewsNotification, object: split)
        }
        liveSplits.removeAll()
        var panes: [NSView] = [editorPane, shellPane, agentPane]
        if let landingView { panes.append(landingView) }
        for pane in panes { pane.removeFromSuperview() }
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

    private func restoreDividers() {
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
        split.setPosition(fraction(for: split.slot) * total, ofDividerAt: 0)
    }

    @objc private func splitViewDidResize(_ note: Notification) {
        guard !isRestoringLayout, let split = note.object as? LayoutSplitView,
              split.arrangedSubviews.count == 2 else { return }
        let total = split.isVertical ? split.bounds.width : split.bounds.height
        guard total > 0 else { return }
        let firstSize = split.isVertical ? split.arrangedSubviews[0].frame.width : split.arrangedSubviews[0].frame.height
        setFraction(max(0.05, min(0.95, firstSize / total)), for: split.slot)
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

    // MARK: Claude binary

    /// Locate the `claude` binary. Falls back to a login-shell `command -v` if the
    /// known path is absent (e.g. on another machine).
    static func resolveClaudeBinary() -> String {
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
