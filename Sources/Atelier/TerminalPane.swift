import AppKit
import SwiftTerm

/// A terminal view whose resizes can be frozen during continuous divider drags
/// (§1.5 latency budget: "PTY resize is debounced to drag-end"). While frozen,
/// frame changes are deferred — the PTY keeps its size and SwiftTerm skips its
/// per-tick reflow; the last deferred size applies once on thaw.
class FreezableTerminalView: LocalProcessTerminalView {
    private var deferredSize: NSSize?

    var resizeFrozen = false {
        didSet {
            guard !resizeFrozen, let size = deferredSize else { return }
            deferredSize = nil
            super.setFrameSize(size)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        if resizeFrozen {
            deferredSize = newSize
        } else {
            super.setFrameSize(newSize)
        }
    }

    /// Fires once, on the first byte the hosted process writes — the resuming
    /// placard's cross-fade-out cue (POLISH_PLAN §5).
    var onFirstData: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        if let callback = onFirstData {
            onFirstData = nil
            DispatchQueue.main.async(execute: callback)
        }
        super.dataReceived(slice: slice)
    }
}

/// One PTY-backed terminal pane. Wraps SwiftTerm's `LocalProcessTerminalView`,
/// applies the Catppuccin Mocha palette, and spawns a process in a pseudo-terminal.
///
/// Both the shell pane and the agent (Claude Code) pane are instances of this —
/// per TECHNICAL_PLAN §1, both are terminal programs and Atelier owns the emulator.
final class TerminalPane: NSView, LocalProcessTerminalViewDelegate, WorkspacePane {
    let terminal: FreezableTerminalView

    /// Focus target for the window's `⌃⌘+hjkl` focus manager.
    var focusView: NSView { terminal }

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
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        applyTheme()
        terminal.processDelegate = self

        // The translucency token reads Reduce Transparency at apply-time (§1.5);
        // re-apply if the user flips it while we're running.
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

    private func applyTheme() {
        terminal.installColors(Theme.ansi)
        // §2.1: the field is translucent over the behind-window blur — glyphs
        // stay full-contrast. SwiftTerm copies this into its layer background
        // only at setup, so set the layer directly too.
        let background = NSColor(swiftTerm: Theme.terminalBackground)
            .withAlphaComponent(Theme.effectiveFieldAlpha)
        terminal.nativeBackgroundColor = background
        terminal.layer?.backgroundColor = background.cgColor
        terminal.nativeForegroundColor = NSColor(swiftTerm: Theme.terminalForeground)
        terminal.caretColor = NSColor(swiftTerm: Theme.terminalCursor)
    }

    @objc private func accessibilityDisplayChanged() {
        applyTheme()
        terminal.needsDisplay = true
    }

    /// Spawn a process in this pane's PTY. `environment` defaults to the inherited
    /// environment with TERM set so full-screen TUIs (Claude Code, hx) render.
    func start(executable: String, args: [String] = [], cwd: String? = nil) {
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
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

    /// Kill the morning dead-terminal flash: until the first PTY byte, a
    /// restoring agent pane shows base material with two muted centered lines —
    /// the session title in mono, `resuming…` in SF Pro — cross-fading out on
    /// first paint. No spinner (§1.1).
    func showResumingPlacard(title: String) {
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

        let resuming = NSTextField(labelWithString: "resuming…")
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

        terminal.onFirstData = { [weak placard] in
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

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTerminated?(exitCode)
    }
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
