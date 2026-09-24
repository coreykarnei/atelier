import AppKit
import SwiftTerm

/// A terminal view whose resizes can be *frozen* (layout rebuilds: only the
/// final geometry may reach the process) or *throttled* (divider drags, since
/// 2026-09-16: the grid follows the pointer live, the PTY hears one resize
/// per beat, the final size lands on release). While frozen, frame changes
/// are deferred — the PTY keeps its size and SwiftTerm skips its per-tick
/// reflow; the last deferred size applies once on thaw.
class FreezableTerminalView: LocalProcessTerminalView {
    private var deferredSize: NSSize?

    /// Consoles, not documents: no scroller at the trailing edge (owner call
    /// 2026-09-10 — a bar that never scrolls anything full-screen is noise).
    override init(frame: CGRect) {
        super.init(frame: frame)
        showsScroller = false
        wheelPrecisionMultiplier = Self.wheelFeel
        copyOnSelect = true // Ghostty parity: highlight is copy (owner call 2026-09-10)
    }

    /// Trackpad wheel feel over the Ghostty-equivalent 1.0 (owner: "still
    /// feels slow", 2026-09-10).
    static let wheelFeel: CGFloat = 1.5

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        showsScroller = false
        wheelPrecisionMultiplier = Self.wheelFeel
        copyOnSelect = true // Ghostty parity: highlight is copy (owner call 2026-09-10)
    }

    /// SwiftTerm wears the text I-beam over the whole grid; these panes are
    /// consoles, not documents — the pointer stays the arrow (owner call
    /// 2026-09-07). `resetCursorRects` is `open` in the vendored copy.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    /// SwiftTerm also sets the I-beam directly on every cursor-update event,
    /// bypassing the rects — same call, arrow.
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// The owner's Ghostty ⌘-chords (dotfiles `ghostty/config`), reproduced
    /// byte for byte so muscle memory carries over: ⌘⌫ kills the line (^U),
    /// ⌘←/→ are Home/End, ⌘⇧←/→ select to line start/end, ⌘↑/↓ are ⌃↑/⌃↓.
    /// Host-level, as in Ghostty — a keymap, not emulator behaviour.
    private static let commandChords: [(key: Character, shift: Bool, bytes: String)] = [
        ("\u{7f}", false, "\u{15}"),
        (Character(UnicodeScalar(NSLeftArrowFunctionKey)!), false, "\u{1b}OH"),
        (Character(UnicodeScalar(NSRightArrowFunctionKey)!), false, "\u{1b}OF"),
        (Character(UnicodeScalar(NSLeftArrowFunctionKey)!), true, "\u{1b}[1;4H"),
        (Character(UnicodeScalar(NSRightArrowFunctionKey)!), true, "\u{1b}[1;4F"),
        (Character(UnicodeScalar(NSUpArrowFunctionKey)!), false, "\u{1b}[1;5A"),
        (Character(UnicodeScalar(NSDownArrowFunctionKey)!), false, "\u{1b}[1;5B"),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), !mods.contains(.control), !mods.contains(.option),
              let key = event.charactersIgnoringModifiers?.first,
              let chord = Self.commandChords.first(where: { $0.key == key && $0.shift == mods.contains(.shift) })
        else { return super.performKeyEquivalent(with: event) }
        send(txt: chord.bytes)
        return true
    }

    var resizeFrozen = false {
        didSet {
            guard !resizeFrozen, let size = deferredSize else { return }
            deferredSize = nil
            applyDeferredSize(size)
        }
    }

    /// Divider drags (2026-09-16, owner call): the grid follows the pointer
    /// *live*, Ghostty-style, but the PTY hears about it at most every
    /// `liveResizeInterval` — one SIGWINCH per beat instead of one per
    /// pointer event, which is what the old drag-end freeze protected the
    /// hosted TUI from. Between beats the last size waits; on release the
    /// final size lands at once. (`resizeFrozen` is the hard freeze layout
    /// rebuilds still use: there a transient 0-column frame must never
    /// reach the process.)
    var resizeThrottled = false {
        didSet {
            guard !resizeThrottled else { return }
            throttleBeat?.cancel()
            throttleBeat = nil
            if let size = deferredSize {
                deferredSize = nil
                applyDeferredSize(size)
            }
        }
    }
    static let liveResizeInterval: TimeInterval = 1.0 / 20
    /// The pending trailing-edge apply. A dispatch item, not a `Timer`: the
    /// drag runs inside NSSplitView's tracking loop, whose run-loop mode
    /// never fires default-mode timers — a `Timer` here waited for mouse-up
    /// and the "live" resize was the first pointer event and nothing more.
    private var throttleBeat: DispatchWorkItem?

    override func setFrameSize(_ newSize: NSSize) {
        if resizeFrozen {
            deferredSize = newSize
        } else if resizeThrottled {
            deferredSize = newSize
            guard throttleBeat == nil else { return } // a beat is already pending
            // Leading edge: the first size of a beat applies now, so the
            // grid moves with the very first pointer event.
            deferredSize = nil
            applyDeferredSize(newSize)
            let beat = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.throttleBeat = nil
                if let size = self.deferredSize {
                    self.deferredSize = nil
                    self.applyDeferredSize(size)
                }
            }
            throttleBeat = beat
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.liveResizeInterval, execute: beat)
        } else {
            super.setFrameSize(newSize)
        }
    }

    private func applyDeferredSize(_ size: NSSize) {
        super.setFrameSize(size)
        // The pane's sliver wash tracks the cell grid; re-lay it out now
        // that the deferred size (and thus the grid) has applied.
        superview?.needsLayout = true
    }

    /// Fires once, on the first byte the hosted process writes — the resuming
    /// placard's cross-fade-out cue (POLISH_PLAN §5).
    var onFirstData: (() -> Void)?

    /// Every write the user makes to the hosted process — keys, paste,
    /// mouse reports — as the bytes sent, after encoding. Observation only.
    var onInput: ((ArraySlice<UInt8>) -> Void)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(data)
        super.send(source: source, data: data)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        if let callback = onFirstData {
            onFirstData = nil
            DispatchQueue.main.async(execute: callback)
        }
        super.dataReceived(slice: slice)
        suppressCaretBlinkIfUnfocused()
    }

    // MARK: Caret blink follows focus

    /// Blink is a focus signal. SwiftTerm draws the unfocused caret hollow but
    /// leaves its blink animation running, so an unfocused pane still pulses —
    /// on a fresh Landing, *two* cursors blink at once. The caret view is
    /// internal to SwiftTerm (found by class name); its blink is suspended
    /// whenever this view isn't first responder and restored on focus.
    /// `dataReceived` (main queue) re-checks because the hosted process can
    /// (re)start the blink via DECSCUSR at any time.

    private var caretLayer: CALayer? {
        subviews.first { String(describing: type(of: $0)).hasSuffix("CaretView") }?.layer
    }
    private var caretWantsBlink = false

    private func suppressCaretBlinkIfUnfocused() {
        guard window?.firstResponder !== self, let layer = caretLayer,
              layer.animation(forKey: "opacity") != nil else { return }
        caretWantsBlink = true
        layer.removeAllAnimations()
        layer.opacity = 1
    }

    /// become/resignFirstResponder aren't open in SwiftTerm, but both funnel
    /// into this open property — the focus signal rides it.
    override var hasFocus: Bool {
        get { super.hasFocus }
        set {
            super.hasFocus = newValue
            if newValue {
                restoreCaretBlink()
            } else {
                // The responder handoff is mid-flight; check after it lands.
                DispatchQueue.main.async { [weak self] in self?.suppressCaretBlinkIfUnfocused() }
            }
        }
    }

    private func restoreCaretBlink() {
        guard caretWantsBlink, let layer = caretLayer,
              layer.animation(forKey: "opacity") == nil else { return }
        // SwiftTerm's own blink, reinstated: 0.7s ease-in autoreverse.
        let anim = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        anim.duration = 0.7
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.fromValue = 1
        anim.toValue = 0
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(anim, forKey: #keyPath(CALayer.opacity))
    }
}

/// One PTY-backed terminal pane. Wraps SwiftTerm's `LocalProcessTerminalView`,
/// applies the Catppuccin Mocha palette, and spawns a process in a pseudo-terminal.
///
/// Both the shell pane and the agent (Claude Code) pane are instances of this —
/// per TECHNICAL_PLAN §1, both are terminal programs and Atelier owns the emulator.
final class TerminalPane: NSView, LocalProcessTerminalViewDelegate, WorkspacePane {
    let terminal: FreezableTerminalView

    /// The cell grid covers `rows × cellHeight` from the top of the terminal
    /// view; the sub-cell remainder strip at the bottom is painted by no cell.
    /// With the terminal's layer clear (the wash lives in the cell fills —
    /// see `applyTheme`), that strip would show raw blur, so this view washes
    /// it from behind, matched to the default-background cells. Behind, not
    /// over: the grid never reaches it, so the wash still paints exactly once.
    private let sliverWash = NSView()

    /// Focus target for the window's `⌃⌘+hjkl` focus manager — the exit card
    /// while the hosted process is dead.
    var focusView: NSView { exitCard ?? terminal }

    /// Called when the hosted process exits, so the host can decide what to do
    /// (e.g. respawn the shell, or mark the agent pane idle).
    var onProcessTerminated: ((Int32?) -> Void)?

    /// - Parameter deguttersCopy: use the agent-pane view that strips Claude's gutter
    ///   from copied text. Off for the shell (its copy is already truthful).
    init(deguttersCopy: Bool = false) {
        terminal = deguttersCopy ? AgentTerminalView(frame: .zero) : FreezableTerminalView(frame: .zero)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        terminal.translatesAutoresizingMaskIntoConstraints = false
        sliverWash.wantsLayer = true
        addSubview(sliverWash)
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        applyScale()
        terminal.processDelegate = self

        // The translucency token reads Reduce Transparency at apply-time (§1.5);
        // re-apply if the user flips it while we're running.
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(typeScaleChanged),
            name: Theme.TypeScale.didChange,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// The terminal face is the *same* face and size as the owner's Ghostty —
    /// JetBrains Mono at the content scale (SwiftTerm's default is the system
    /// mono at 13, which is what made Atelier read subtly denser than the
    /// reference). Setting the font runs SwiftTerm's setupOptions, which
    /// re-copies the wash into the layer — applyTheme must follow to keep the
    /// layer clear (single-wash rule).
    private func applyScale() {
        terminal.font = Theme.Typography.mono(Theme.TypeScale.current)
        applyTheme()
        positionWash()
    }

    @objc private func typeScaleChanged() {
        applyScale()
        terminal.needsDisplay = true
    }

    private func applyTheme() {
        terminal.installColors(Theme.ansi)
        // §2.1: the field is translucent over the behind-window blur — glyphs
        // stay full-contrast. The wash must be painted exactly *once*:
        // SwiftTerm fills every cell's background (default cells use
        // nativeBackgroundColor, alpha'd here), so the view's layer stays
        // clear — layer wash + cell fills would stack to ~2× the token,
        // which is what made the window read as opaque. (SwiftTerm only
        // copies nativeBackgroundColor into the layer during setupOptions —
        // init/font changes — so clearing it here holds.)
        let background = NSColor(swiftTerm: Theme.terminalBackground)
            .withAlphaComponent(Theme.effectiveFieldAlpha)
        terminal.nativeBackgroundColor = background
        terminal.layer?.backgroundColor = NSColor.clear.cgColor
        sliverWash.layer?.backgroundColor = background.cgColor
        terminal.nativeForegroundColor = NSColor(swiftTerm: Theme.terminalForeground)
        terminal.caretColor = NSColor(swiftTerm: Theme.terminalCursor)
    }

    /// Size the wash strip to exactly the height the grid leaves uncovered,
    /// and clip the terminal to the grid so the two can never overlap. The
    /// clip matters because SwiftTerm sometimes paints the sub-cell strip
    /// itself (a partial scrollback row in the normal buffer) and sometimes
    /// cannot (alt-screen TUIs — Claude, hx — have no scrollback): translucent
    /// washes may be painted exactly once, so the strip has exactly one owner.
    /// Frame-set (not constrained): the split positions panes imperatively,
    /// and the grid can move without a pane-frame change, so this is
    /// recomputed from every authority that can move it — pane resize,
    /// layout, and SwiftTerm's own grid resize (`sizeChanged`).
    private func positionWash() {
        let sliver = max(0, terminal.frame.height - terminal.getOptimalFrameSize().height)
        let target = NSRect(x: 0, y: 0, width: bounds.width, height: sliver)
        if sliverWash.frame != target { sliverWash.frame = target }
        guard let layer = terminal.layer else { return }
        let grid = CGRect(x: 0, y: sliver, width: bounds.width, height: max(0, terminal.frame.height - sliver))
        let mask = layer.mask as? CAShapeLayer ?? CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: terminal.frame.size)
        mask.path = CGPath(rect: grid, transform: nil)
        if layer.mask !== mask { layer.mask = mask }
    }

    override func layout() {
        super.layout()
        positionWash()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    /// Dev-only (the snapshot debug's state dump): the live wash geometry, so
    /// alpha-channel probes of snapshots can be reconciled with what the view
    /// tree actually holds.
    var debugWashState: String {
        let layerAlpha = terminal.layer.map { String(format: "%.3f", $0.backgroundColor?.alpha ?? -1) } ?? "nil-layer"
        return "terminal bounds=\(terminal.bounds) optimal=\(terminal.getOptimalFrameSize())"
            + " layerBGAlpha=\(layerAlpha) sliverWash=\(sliverWash.frame)"
            + " nativeBGAlpha=\(String(format: "%.3f", terminal.nativeBackgroundColor.alphaComponent))"
    }

    @objc private func accessibilityDisplayChanged() {
        applyTheme()
        terminal.needsDisplay = true
    }

    /// Spawn a process in this pane's PTY, with TERM set so full-screen TUIs
    /// (Claude Code, hx) render. `loginEnvironment` hands the process what
    /// the owner's interactive zsh would (PATH above all) — for programs
    /// spawned directly rather than through a login shell.
    func start(executable: String, args: [String] = [], cwd: String? = nil, loginEnvironment: Bool = false,
               extraEnvironment: [String] = []) {
        let terminalEnv = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        var env = loginEnvironment ? LoginEnvironment.entries(overriding: terminalEnv) : terminalEnv
        env.append(contentsOf: extraEnvironment)
        if let cwd {
            // The spawned child inherits the parent's working directory; set it here
            // so the pane opens in `cwd` rather than `/`. (Per-pane cwd for worktrees
            // is Milestone 1 — for now both panes share one root.)
            FileManager.default.changeCurrentDirectoryPath(cwd)
            env.append("PWD=\(cwd)")
            // The agent pane needs its cwd to find Claude's transcript for truthful copy.
            (terminal as? AgentTerminalView)?.transcriptCwd = cwd
        }
        terminal.startProcess(executable: executable, args: args, environment: env, execName: nil)
    }

    /// Kill the hosted process (used when a session is closed).
    func terminate() {
        terminal.terminate()
    }

    /// Type into the hosted process's PTY — used to re-root the shell on session
    /// promote, the same move the `ide` script makes with tmux send-keys.
    func send(text: String) {
        let bytes = Array(text.utf8)
        terminal.process?.send(data: bytes[...])
    }

    /// PID of the hosted process (nil before `start`).
    var hostedPid: pid_t? {
        guard let process = terminal.process, process.shellPid != 0 else { return nil }
        return process.shellPid
    }

    // MARK: Resuming placard (POLISH_PLAN §5)

    /// The placard currently covering this pane, if any — reconnect retries
    /// must re-arm the existing one, not stack a second.
    private weak var currentPlacard: NSView?

    /// Kill the morning dead-terminal flash: until the first PTY byte, a
    /// restoring (or reconnecting) pane shows base material with two muted
    /// centered lines — the session title in mono, the state in SF Pro —
    /// cross-fading out on first paint. No spinner (§1.1).
    ///
    /// `onFirstData` (optional) also runs on that first byte — the reattach
    /// loop uses it to reset its backoff. Idempotent while a placard is up:
    /// repeated calls only re-arm the first-data hook.
    func showResumingPlacard(
        title: String,
        subtitle: String = "resuming…",
        onFirstData extra: (() -> Void)? = nil
    ) {
        if let placard = currentPlacard {
            armPlacardDismissal(placard, extra: extra)
            return
        }
        let placard = NSView()
        placard.wantsLayer = true
        placard.layer?.backgroundColor = Theme.Elevation.base.cgColor
        placard.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Theme.Typography.mono(Theme.Typography.body, weight: .medium)
        titleLabel.textColor = Theme.chromeText
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        placard.addSubview(titleLabel)

        let resuming = NSTextField(labelWithString: subtitle)
        resuming.font = Theme.Typography.ui(Theme.Typography.small)
        resuming.textColor = Theme.chromeMutedText
        resuming.translatesAutoresizingMaskIntoConstraints = false
        placard.addSubview(resuming)

        addSubview(placard)
        NSLayoutConstraint.activate([
            placard.topAnchor.constraint(equalTo: topAnchor),
            placard.bottomAnchor.constraint(equalTo: bottomAnchor),
            placard.leadingAnchor.constraint(equalTo: leadingAnchor),
            placard.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: placard.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: placard.centerYAnchor, constant: -10),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: placard.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: placard.trailingAnchor, constant: -20),
            resuming.centerXAnchor.constraint(equalTo: placard.centerXAnchor),
            resuming.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
        ])

        currentPlacard = placard
        armPlacardDismissal(placard, extra: extra)
    }

    private func armPlacardDismissal(_ placard: NSView, extra: (() -> Void)?) {
        terminal.onFirstData = { [weak placard] in
            extra?()
            guard let placard else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                placard.removeFromSuperview()
                return
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                placard.animator().alphaValue = 0
            }, completionHandler: { placard.removeFromSuperview() })
        }
    }

    // MARK: Exit card

    private var exitCard: ExitCardView?

    /// The hosted process ended and the pane is dead: cover it with the
    /// placard's material and two ways back in, instead of leaving the last
    /// screenful as a dead end. Keyboard-first — the card takes focus if the
    /// pane had it, `↩` resumes, `⇧↩` starts fresh.
    func showExitCard(
        title: String,
        subtitle: String,
        onResume: @escaping () -> Void,
        onNew: @escaping () -> Void
    ) {
        currentPlacard?.removeFromSuperview()
        currentPlacard = nil
        exitCard?.removeFromSuperview()

        let hadFocus = window.map { fr in
            fr.firstResponder === terminal || (fr.firstResponder as? NSView)?.isDescendant(of: self) == true
        } ?? false

        // Wipe the dead screen now: the card's material is translucent (one
        // wash over the blur), and a resumed Claude repaints its own
        // conversation — the old copy would read through, then read twice.
        // The caret hides too, or it blinks at the origin through the card.
        terminal.feed(text: "\u{1b}c\u{1b}[?25l")

        let card = ExitCardView(title: title, subtitle: subtitle)
        card.onResume = { [weak self] in self?.dismissExitCard(then: onResume) }
        card.onNew = { [weak self] in self?.dismissExitCard(then: onNew) }
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        exitCard = card
        if hadFocus { window?.makeFirstResponder(card) }
    }

    private func dismissExitCard(then respawn: () -> Void) {
        guard let card = exitCard else { return }
        let hadFocus = window?.firstResponder === card
        exitCard = nil
        card.removeFromSuperview()
        terminal.feed(text: "\u{1b}[?25h")
        respawn()
        if hadFocus { window?.makeFirstResponder(terminal) }
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        positionWash()
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTerminated?(exitCode)
    }
}

/// What a pane shows once its hosted process has ended: the resuming
/// placard's material and type (title in mono, state in SF Pro), with the
/// two ways back in beneath — the placard's arrival state and the exit
/// card's departure state read as one family.
private final class ExitCardView: NSView {
    var onResume: (() -> Void)?
    var onNew: (() -> Void)?

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.base.cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = Theme.Typography.mono(Theme.Typography.body, weight: .medium)
        titleLabel.textColor = Theme.chromeText
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let state = NSTextField(labelWithString: subtitle)
        state.font = Theme.Typography.ui(Theme.Typography.small)
        state.textColor = Theme.chromeMutedText
        state.translatesAutoresizingMaskIntoConstraints = false
        addSubview(state)

        let resume = KeyActionButton(keyHint: "↩")
        resume.actionTitle = "Resume session"
        resume.target = self
        resume.action = #selector(resumeTapped)
        let fresh = KeyActionButton(keyHint: "⇧↩")
        fresh.actionTitle = "New session"
        fresh.target = self
        fresh.action = #selector(newTapped)

        let buttons = NSStackView(views: [resume, fresh])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttons)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -28),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            state.centerXAnchor.constraint(equalTo: centerXAnchor),
            state.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            buttons.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttons.topAnchor.constraint(equalTo: state.bottomAnchor, constant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 36 || event.keyCode == 76, // return, keypad enter
              mods.subtracting(.shift).isEmpty
        else { return super.keyDown(with: event) }
        if mods.contains(.shift) { newTapped() } else { resumeTapped() }
    }

    @objc private func resumeTapped() { onResume?() }
    @objc private func newTapped() { onNew?() }
}

private extension NSColor {
    convenience init(swiftTerm c: SwiftTerm.Color) {
        self.init(
            srgbRed: CGFloat(c.red) / 65535.0,
            green: CGFloat(c.green) / 65535.0,
            blue: CGFloat(c.blue) / 65535.0,
            alpha: 1.0
        )
    }
}
