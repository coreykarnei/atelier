import AppKit
import AtelierIPC

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

    /// Per-tab attention (MILESTONE_1 §7.1): the agent's exact state, always
    /// visible on the tab. Once a session has run, it is essentially always
    /// either working or waiting — `none` is the never-prompted state.
    ///
    /// RULE — no escalation (POLISH_PLAN §1.3, same standing as the keymap):
    /// a waiting session never pulses harder, never re-notifies, never changes
    /// color with age. The truth is always available at every distance and it
    /// never raises its voice. Elapsed time is available **on inquiry** (the
    /// tab tooltip), never pushed. Any change that makes one of these states
    /// loudness-vary over time is wrong by rule, not by taste.
    enum Attention: String {
        case none
        case working      // agent mid-turn (blue dot)
        case waiting      // turn done, your move (green dot)
        case needsInput   // agent explicitly blocked — permission/question (peach dot)
        case doneUnseen   // finished while you were elsewhere (ringing green → waiting on focus)
        case needsInputUnseen // blocked while you were elsewhere (ringing peach → needsInput on focus)

        /// The two states that arrived while you were looking elsewhere —
        /// the only marks that move to catch your eye (the ring).
        var isUnseen: Bool { self == .doneUnseen || self == .needsInputUnseen }

        /// What the state becomes once you've looked: the ring stops, the
        /// colour and the meaning stay.
        var seen: Attention {
            switch self {
            case .doneUnseen: return .waiting
            case .needsInputUnseen: return .needsInput
            default: return self
            }
        }
    }

    let id = UUID()
    private(set) var state: State = .landing
    private(set) var cwd: String
    /// Where the hosted processes run. Remote sessions spawn both panes over
    /// ssh into host-side tmux; `cwd` then holds the *remote* directory.
    let location: SessionLocation
    var isRemote: Bool { location.isRemote }
    /// Lowercased to match Claude's on-disk transcript filename. Replaced
    /// when the exit card's New session starts a fresh conversation here.
    private(set) var claudeSessionId: String
    /// Names this session's host-side tmux sessions. The birth
    /// `claudeSessionId`, fixed for life: a new conversation in the tab must
    /// not orphan the remote shell it shares the tab with.
    let tmuxKey: String
    /// True when this session came back from disk — the agent then *resumes* its
    /// previous Claude conversation instead of starting a fresh one.
    private let isRestored: Bool

    let editorPane = EditorPane(frame: .zero)
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
    var attention: Attention = .none {
        didSet { if oldValue != attention { attentionSince = Date() } }
    }

    /// When the current attention state began — the tooltip's "working · 4m"
    /// (§4: time on inquiry, zero always-on pixels).
    private(set) var attentionSince: Date?

    /// The label the tab actually shows.
    var displayTitle: String { customTitle ?? title }

    /// True when this session's root is a linked worktree (not the primary
    /// checkout) — drives the ⎇ glyph and tab grouping.
    var isWorktree: Bool {
        cwd.hasPrefix(WorktreeManager.base + "/")
    }

    /// Fired after the session is promoted to an IDE session, so the window can
    /// refresh the project pill, tab strip, and focus.
    var onPromoted: (() -> Void)?

    /// A Landing chose a remote target. Promotion-in-place can't cross
    /// machines (the landing shell's PTY is local), so the window controller
    /// replaces this Landing with a fresh remote session in the same tab slot.
    var onRemoteRequested: ((_ host: String, _ dir: String) -> Void)?

    /// Asked before a Landing promotes onto `root`; returning true means the
    /// window controller took the pick itself (a shelved project on that
    /// root came back in this Landing's place) and this Landing must not
    /// promote.
    var onPromoteRequested: ((_ root: String) -> Bool)?

    /// Attention changed from inside the session (the agent exited), not
    /// from a hook event — the tab strip must re-read it.
    var onAttentionChanged: (() -> Void)?

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
        self.tmuxKey = claudeSessionId
        self.isRestored = false
        self.location = .local
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false

        let landing = LandingView(defaultFolder: cwd)
        landing.onOpen = { [weak self] path in self?.promote(to: path) }
        landing.onOpenRemote = { [weak self] host, dir in self?.onRemoteRequested?(host, dir) }
        landing.liveCwd = { [weak self] in
            self?.shellPane.hostedPid.flatMap(ProcessCwd.cwd(of:))
        }
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
        self.tmuxKey = claudeSessionId
        self.isRestored = false
        self.location = .local
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false
        editorPane.setRoot(ideRoot)
        rebuildLayout()
    }

    /// A session born remote: shell + agent on `host` over ssh, rooted at
    /// `remoteDir` (`~`-relative or absolute, on the *remote* filesystem).
    /// Always an IDE session in Split — there is no Landing stage on a remote
    /// (the pick already happened) and no editor (the files aren't here).
    init(remoteHost: String, remoteDir: String) {
        self.cwd = remoteDir
        self.title = remoteDir == "~"
            ? remoteHost
            : (remoteDir as NSString).lastPathComponent
        self.state = .ide
        self.claudeSessionId = UUID().uuidString.lowercased()
        self.tmuxKey = claudeSessionId
        self.isRestored = false
        self.location = .remote(host: remoteHost)
        self.layoutMode = .split
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
        self.tmuxKey = restored.tmuxKey ?? restored.claudeSessionId
        self.isRestored = true
        self.location = restored.remoteHost.map { .remote(host: $0) } ?? .local
        self.state = restored.isIDE ? .ide : .landing
        // What relaunch can honestly say: a resumed agent is idle, so a turn
        // that was mid-flight or blocked comes back as plain waiting (the
        // prompt that blocked it died with the process); an unseen
        // completion stays unseen until you look (owner ask 2026-09-10).
        switch restored.attention.flatMap(Attention.init(rawValue:)) ?? .none {
        case .doneUnseen: self.attention = .doneUnseen
        case .waiting, .working, .needsInput, .needsInputUnseen: self.attention = .waiting
        case .none: break
        }
        let restoredMode = LayoutMode(rawValue: restored.layoutMode) ?? .triptych
        self.layoutMode = restored.remoteHost == nil
            ? restoredMode
            : (restoredMode == .splitSide ? .splitSide : .split)
        self.dividers = restored.dividers.mapValues { CGFloat($0) }
        super.init()
        container.translatesAutoresizingMaskIntoConstraints = false

        if state == .landing {
            let landing = LandingView(defaultFolder: cwd)
            landing.onOpen = { [weak self] path in self?.promote(to: path) }
            landing.onOpenRemote = { [weak self] host, dir in self?.onRemoteRequested?(host, dir) }
            landing.liveCwd = { [weak self] in
                self?.shellPane.hostedPid.flatMap(ProcessCwd.cwd(of:))
            }
            landingView = landing
        }
        rebuildLayout()

        if state == .ide, !isRemote { editorPane.setRoot(cwd) }
        // The open file rides persistence (M2.1): reopen it if it's still there.
        if state == .ide, let file = restored.openFile,
           FileManager.default.fileExists(atPath: file) {
            try? editorPane.open(path: file)
        }
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
            tmuxKey: tmuxKey == claudeSessionId ? nil : tmuxKey,
            dividers: dividers.mapValues { Double($0) },
            openFile: editorPane.committedFilePath,
            remoteHost: location.host,
            attention: attention.rawValue
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
        agentPane.terminal.onInput = { [weak self] bytes in self?.agentInput(bytes) }
        switch location {
        case .local:
            shellPane.start(executable: "/bin/zsh", args: ["-l"], cwd: cwd)
        case .remote(let host):
            // A login shell, like tmux's default — but with COLORTERM set
            // explicitly: the conf's set-environment races the initial
            // session's pane creation (observed), and truecolor programs in
            // the pane check the env, not the terminal.
            startRemotePane(
                shellPane, host: host, suffix: "sh",
                command: "sh -c 'COLORTERM=truecolor exec \"$SHELL\" -l'"
            )
        }
        if state == .ide { startAgent() }
    }

    /// Promote this Landing into an IDE session rooted at `root`: re-root the shell,
    /// spawn Claude there, switch to the Triptych. One-way; no-op if already an IDE.
    func promote(to root: String) {
        guard state == .landing else { return }
        if onPromoteRequested?(root) == true { return }
        state = .ide
        cwd = root
        title = (root as NSString).lastPathComponent
        RecentsStore.record(root)

        // Re-root the live shell — same move the `ide` script makes (send-keys cd).
        shellPane.send(text: " cd '\(root)' && clear\r")
        editorPane.setRoot(root)
        startAgent()

        rebuildLayout()
        landingView = nil
        onPromoted?()
    }

    private var agentStarted = false

    private func startAgent() {
        guard !agentStarted else { return }
        agentStarted = true
        // §5: the notification-permission prompt fires the moment the first
        // agent exists — promote or restore — not at app launch.
        NotificationPermission.requestOnce()
        spawnAgent(resume: isRestored)
    }

    /// Spawn Claude in the agent pane. `resume` matters only remotely — the
    /// transcript lives on the host, so the caller says whether one exists;
    /// locally the transcript on disk decides.
    private func spawnAgent(resume: Bool) {
        if case .remote(let host) = location {
            // A login shell so the remote PATH resolves claude; `--session-id`
            // is still app-chosen so transcripts and (M-remote phase 3) hook
            // events join on the same id. On a restored session the command
            // resumes — but `new -A` only *runs* it when the tmux session is
            // gone; if claude is still alive out there we just reattach to it,
            // mid-conversation, which no local `--resume` can match.
            let flag = resume ? "--resume" : "--session-id"
            if resume {
                // At launch the tmux session may still hold a live claude;
                // after an exit there is nothing to reattach to.
                agentPane.showResumingPlacard(
                    title: displayTitle,
                    subtitle: agentHasExited ? "resuming…" : "reattaching to \(host)…"
                )
            }
            // The unsets matter as much as COLORTERM: Claude Code fingerprints
            // tmux via TMUX/TERM_PROGRAM and self-downgrades to indexed-256
            // (ignoring COLORTERM and even FORCE_COLOR) — the owner's "muted"
            // pane. tmux itself passes RGB fine (Tc); hide the fingerprints
            // and claude emits truecolor. Verified against jarvis 2026-07-14.
            startRemotePane(
                agentPane, host: host, suffix: "ai",
                command: "bash -lc \"unset TMUX TMUX_PANE TERM_PROGRAM TERM_PROGRAM_VERSION;"
                    + " COLORTERM=truecolor \(tabEnvironment) exec claude \(flag) \(claudeSessionId)\""
            )
            return
        }

        let claude = Session.resolveClaudeBinary()
        // Resume whenever Claude already has a transcript under this id (a
        // restored session, or a reopened one); `--session-id` on a known id
        // is refused as "already in use". Otherwise start fresh under the id.
        let args: [String]
        if Self.transcriptExists(sessionId: claudeSessionId, cwd: cwd) {
            args = ["--resume", claudeSessionId]
            agentPane.showResumingPlacard(title: displayTitle)
        } else {
            args = ["--session-id", claudeSessionId]
        }
        agentPane.start(executable: claude, args: args, cwd: cwd, loginEnvironment: true,
                        extraEnvironment: [tabEnvironment])
        agentPane.onProcessTerminated = { [weak self] code in
            guard let self else { return }
            NSLog("Atelier: agent process exited (session \(self.id), code: \(String(describing: code)))")
            self.agentExited()
        }
    }

    /// Answering a permission prompt fires no hook (Claude Code has none for
    /// "approved"; the next is PostToolUse, when the approved tool *ends* —
    /// a long build would stay peach throughout). The answer is typed here,
    /// though, so the host reads it: confirming (↩, or a menu digit) means
    /// the agent is moving again, Esc means it stopped and it's your move.
    /// A guess the hooks overrule within moments — a denial ends the turn
    /// (Stop), a tool finishing reports working — and only ever made while
    /// the session is blocked; every other state belongs to the hooks alone.
    private func agentInput(_ bytes: ArraySlice<UInt8>) {
        guard attention == .needsInput || attention == .needsInputUnseen else { return }
        switch PromptAnswer(bytes) {
        case .confirm: attention = .working
        case .dismiss: attention = .waiting
        case nil: return
        }
        onAttentionChanged?()
    }

    /// `ATELIER_TAB=<this tab>` for the agent, so every hook it fires names
    /// this tab whatever conversation it's in (see `adoptConversation`).
    private var tabEnvironment: String { "\(NotifyMessage.tabEnvironmentKey)=\(id.uuidString)" }

    /// A hook from this tab's agent reported a different conversation:
    /// `/resume` or `/clear` inside Claude moved it (owner report
    /// 2026-09-23: tabs stuck on the repo name, no dot, their hooks dropped
    /// under an id nothing knew). Follow it — the title, the dots, banner
    /// clicks, and relaunch's `--resume` all key on `claudeSessionId`.
    func adoptConversation(_ sessionId: String) {
        let id = sessionId.lowercased()
        guard id != claudeSessionId else { return }
        NSLog("Atelier: tab \(self.id) followed its agent from \(claudeSessionId) to \(id)")
        claudeSessionId = id
    }

    /// Claude ended (`/exit`, ⌃C⌃C, a crash, a kill). The tab stays; the pane
    /// offers the way back in — this conversation, or a fresh one here.
    private var agentHasExited = false

    private func agentExited() {
        guard !intentionalTeardown else { return }
        agentHasExited = true
        if attention != .none {
            attention = .none
            onAttentionChanged?()
        }
        agentPane.showExitCard(
            title: displayTitle,
            subtitle: "Claude exited",
            onResume: { [weak self] in self?.spawnAgent(resume: true) },
            onNew: { [weak self] in
                guard let self else { return }
                self.claudeSessionId = UUID().uuidString.lowercased()
                self.spawnAgent(resume: false)
            }
        )
    }

    // MARK: Remote panes

    /// Consecutive failed reconnects per pane — indexes the backoff ladder,
    /// reset by the first byte of a live connection.
    private var reconnectAttempts: [ObjectIdentifier: Int] = [:]

    /// Set the moment this session is deliberately torn down, so a dying ssh
    /// client is not mistaken for link death and reattached.
    private var intentionalTeardown = false

    /// Spawn one pane's ssh→tmux chain and arm the reattach loop. The same
    /// argv is respawned verbatim on link death — `tmux new -A` turns every
    /// respawn into a reattach.
    private func startRemotePane(_ pane: TerminalPane, host: String, suffix: String, command: String?) {
        RemoteLink.link(for: host).activate()
        let argv = RemoteCommand.paneArgv(
            host: host,
            tmuxSession: RemoteCommand.tmuxSessionName(key: tmuxKey, pane: suffix),
            remoteDir: cwd,
            command: command
        )
        pane.onProcessTerminated = { [weak self, weak pane] code in
            guard let self, let pane else { return }
            self.remotePaneExited(pane, host: host, argv: argv, code: code)
        }
        pane.start(executable: RemoteCommand.sshPath, args: argv, cwd: nil)
    }

    /// Link death → placard + backoff respawn, forever (a rebooting host takes
    /// as long as it takes). Anything else — typed `exit`, tmux kill — is a
    /// deliberate end and the pane goes idle, exactly like a local shell's.
    private func remotePaneExited(_ pane: TerminalPane, host: String, argv: [String], code: Int32?) {
        guard !intentionalTeardown else { return }
        guard RemoteCommand.isLinkFailure(code) else {
            NSLog("Atelier: remote pane ended (session \(id), code: \(String(describing: code)))")
            if pane === agentPane { agentExited() }
            return
        }
        let key = ObjectIdentifier(pane)
        let attempt = reconnectAttempts[key, default: 0]
        reconnectAttempts[key] = attempt + 1
        let delay = [1.0, 2.0, 5.0][min(attempt, 2)]
        pane.showResumingPlacard(title: displayTitle, subtitle: "reconnecting to \(host)…") {
            [weak self] in self?.reconnectAttempts[key] = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak pane] in
            guard let self, let pane, !self.intentionalTeardown else { return }
            // The notify forward likely died with the same network event.
            RemoteLink.link(for: host).activate()
            pane.start(executable: RemoteCommand.sshPath, args: argv, cwd: nil)
        }
    }

    /// Whether Claude already holds a transcript under this id — the same
    /// resolver the tab titles use (Claude's project-dir encoding turns every
    /// non-alphanumeric character into `-`, underscores included; a private
    /// copy here once kept `_` and sent restored BCI_HW1 sessions down the
    /// `--session-id` path, which Claude refuses as "already in use").
    private static func transcriptExists(sessionId: String, cwd: String) -> Bool {
        TranscriptTitle.transcriptPath(sessionId: sessionId, cwd: cwd) != nil
    }

    /// Terminate the hosted processes when the session is closed.
    ///
    /// For a remote session the local ssh clients always die, but the tmux'd
    /// work on the host dies only on a *deliberate* close (`killRemote`, the
    /// default). Quit paths pass `false`: the work stays running out there and
    /// relaunch reattaches to it.
    func terminate(killRemote: Bool = true) {
        intentionalTeardown = true
        shellPane.terminate()
        if agentStarted { agentPane.terminate() }
        if killRemote, shellStarted, case .remote(let host) = location {
            RemoteCommand.killRemoteSessions(host: host, key: tmuxKey)
        }
    }

    // MARK: Focus

    /// The pane that should receive focus when this session is shown. A Landing
    /// is opener-first (owner revision 2026-07-13, reversing M1's terminal-first):
    /// ⌘T means "open a project," so the first keystroke lands in the filter
    /// field; the shell below is one ⌃⌘j away.
    var defaultFocusView: NSView {
        switch state {
        case .landing: return landingView?.focusView ?? shellPane.terminal
        case .ide: return agentPane.focusView
        }
    }

    /// Re-scan the Landing's offer (recents/repos). Cheap; called whenever the
    /// tab is shown so the list is never stale.
    func refreshLanding() {
        landingView?.refresh()
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
            case .splitSide: return [shellPane, agentPane]
            }
        }
    }

    // MARK: Focus articulation (POLISH_PLAN Phase 1)

    /// Hairline views along the focused pane's divider edges. Constraint-pinned
    /// to the pane, so they ride divider drags for free.
    private var focusLines: [NSView] = []
    private weak var focusArticulatedPane: WorkspacePane?

    /// Re-aim the focus hairline at whichever pane owns the first responder.
    /// Non-key windows drop the hairline (§3 "the window as an object") — the
    /// truth of *which pane* returns with key status. Never dims anything.
    func updateFocusArticulation(firstResponder: NSResponder?, windowIsKey: Bool) {
        let pane = visiblePanes.first { pane in
            guard let fr = firstResponder as? NSView else { return false }
            return fr === pane.focusView || fr.isDescendant(of: pane)
        }
        guard windowIsKey, let pane else {
            clearFocusLines()
            return
        }
        if pane !== focusArticulatedPane || focusLines.isEmpty {
            layFocusLines(around: pane)
            focusArticulatedPane = pane
        }
    }

    /// Make both terminals' carets truthful about window key status: SwiftTerm
    /// hollows the caret on resignFirstResponder but doesn't watch the window,
    /// so a background window would keep a solid block. Solid means "typing
    /// goes here", and in a non-key window it doesn't.
    func syncCaretFocus(firstResponder: NSResponder?, windowIsKey: Bool) {
        for pane in [shellPane, agentPane] {
            let isFocused = (firstResponder as? NSView) === pane.terminal
            pane.terminal.hasFocus = windowIsKey && isFocused
        }
    }

    /// The ~150 ms glow-then-settle when focus jumps via `⌃⌘+hjkl` (§3). One
    /// event, one motion, then stillness. Reduce Motion: no glow, just the line.
    func glowFocus() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        for line in focusLines {
            guard let layer = line.layer else { continue }
            let glow = CABasicAnimation(keyPath: "opacity")
            glow.fromValue = 1.0
            glow.toValue = Theme.Focus.restingOpacity
            glow.duration = Theme.Focus.glowDuration
            glow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(glow, forKey: "focusGlow")
        }
    }

    private func clearFocusLines() {
        for line in focusLines { line.removeFromSuperview() }
        focusLines.removeAll()
        focusArticulatedPane = nil
    }

    /// Pin 1 px lavender lines along the pane's *interior* edges — the ones that
    /// face a divider. Edges flush with the session container are window edges
    /// and stay unmarked.
    private func layFocusLines(around pane: WorkspacePane) {
        clearFocusLines()
        container.layoutSubtreeIfNeeded()
        let frame = pane.convert(pane.bounds, to: container)
        guard frame.width > 1, frame.height > 1 else { return }
        let bounds = container.bounds

        func line() -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.translatesAutoresizingMaskIntoConstraints = false
            view.layer?.backgroundColor = Theme.Focus.hairline.cgColor
            view.layer?.opacity = Theme.Focus.restingOpacity
            container.addSubview(view)
            focusLines.append(view)
            return view
        }

        if frame.minX > 1 { // divider to the left
            let v = line()
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
                v.topAnchor.constraint(equalTo: pane.topAnchor),
                v.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
                v.widthAnchor.constraint(equalToConstant: 1),
            ])
        }
        if frame.maxX < bounds.maxX - 1 { // divider to the right
            let v = line()
            NSLayoutConstraint.activate([
                v.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
                v.topAnchor.constraint(equalTo: pane.topAnchor),
                v.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
                v.widthAnchor.constraint(equalToConstant: 1),
            ])
        }
        if frame.maxY < bounds.maxY - 1 { // divider above (AppKit y grows upward)
            let v = line()
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: pane.topAnchor),
                v.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
                v.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
        if frame.minY > 1 { // divider below
            let v = line()
            NSLayoutConstraint.activate([
                v.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
                v.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
    }

    // MARK: Layout

    /// Toggle the layout. Meaningless for a Landing, so a no-op there.
    /// Remote sessions never show the editor (it edits *local* files), so
    /// their ⌘\ cycles the two-pane arrangements instead: stacked ↔
    /// side-by-side.
    func toggleLayout() {
        guard state == .ide else { return }
        layoutMode = isRemote ? layoutMode.nextSplit : layoutMode.next
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
    ///
    /// PTY resizes are frozen for the duration (§1.5, same rule as divider
    /// drags): re-parenting walks the terminals through degenerate transient
    /// frames, and a 0-column resize reaching the hosted process can kill it —
    /// observed as the remote claude dying on a ⌘\ toggle. Only the final
    /// geometry may land.
    private func rebuildLayout() {
        shellPane.terminal.resizeFrozen = true
        agentPane.terminal.resizeFrozen = true
        defer {
            shellPane.terminal.resizeFrozen = false
            agentPane.terminal.resizeFrozen = false
        }
        tearDownCurrentLayout()

        let root: NSView
        switch state {
        case .landing:
            root = makeSplit(slot: LayoutSlots.landingVertical, vertical: false, first: landingView!, second: shellPane)
        case .ide:
            switch layoutMode {
            case .triptych:
                let leftColumn = makeSplit(slot: LayoutSlots.triptychInner, vertical: false, first: editorPane, second: shellPane)
                let outer = makeSplit(slot: LayoutSlots.triptychOuter, vertical: true, first: leftColumn, second: agentPane)
                outer.installCornerHandle(inner: leftColumn)
                root = outer
            case .split:
                root = makeSplit(slot: LayoutSlots.splitVertical, vertical: false, first: agentPane, second: shellPane)
            case .splitSide:
                root = makeSplit(slot: LayoutSlots.splitSide, vertical: true, first: shellPane, second: agentPane)
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
        clearFocusLines()
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
        split.arrangesAllSubviews = false // the corner handle floats, unarranged
        split.slot = slot
        split.isVertical = vertical
        split.dividerStyle = .thin
        split.delegate = self
        split.onDividerDrag = { [weak self] dragging in
            guard let self else { return }
            // §1.5 revised 2026-09-16 (owner call): the grid follows the
            // pointer live, the PTY hears about it at a throttled beat, and
            // the final size lands on release — see `resizeThrottled`.
            self.shellPane.terminal.resizeThrottled = dragging
            self.agentPane.terminal.resizeThrottled = dragging
        }
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
        // The inner divider moved: the outer's corner handle must follow.
        ((note.object as? NSView)?.superview as? LayoutSplitView)?.needsLayout = true
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

/// How a keystroke answers a permission prompt, read from the bytes the
/// terminal sent — both encodings Claude may have asked for: legacy
/// (`\r`, a lone ESC) and the kitty keyboard protocol (`CSI 13 u`,
/// `CSI 27 u`, with or without a modifier field). A digit picks a menu
/// row and answers at once (a key release, `CSI 13;1:3 u`, reads as the
/// same answer — harmless, the state has already moved). Anything else — arrows moving the highlight,
/// a paste, a mouse report — isn't an answer.
enum PromptAnswer {
    case confirm
    case dismiss

    init?(_ bytes: ArraySlice<UInt8>) {
        let b = Array(bytes)
        if b == [0x0D] || b == [0x0A] { self = .confirm; return }
        if b == [0x1B] { self = .dismiss; return }
        if b.count == 1, (0x31...0x39).contains(b[0]) { self = .confirm; return }
        // CSI <code> [; <mods>] u
        guard b.count >= 4, b[0] == 0x1B, b[1] == 0x5B, b.last == 0x75 else { return nil }
        let body = String(decoding: b[2..<(b.count - 1)], as: UTF8.self)
        // The key code is the first `:`-field of the first `;`-field.
        guard let field = body.split(separator: ";").first?.split(separator: ":").first,
              let code = Int(field) else { return nil }
        switch code {
        case 13, 49...57: self = .confirm // ↩, or a digit under "report all keys"
        case 27: self = .dismiss
        default: return nil
        }
    }
}
