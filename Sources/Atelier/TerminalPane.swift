import AppKit
import SwiftTerm

/// One PTY-backed terminal pane. Wraps SwiftTerm's `LocalProcessTerminalView`,
/// applies the Catppuccin Mocha palette, and spawns a process in a pseudo-terminal.
///
/// Both the shell pane and the agent (Claude Code) pane are instances of this —
/// per TECHNICAL_PLAN §1, both are terminal programs and Atelier owns the emulator.
final class TerminalPane: NSView, LocalProcessTerminalViewDelegate, WorkspacePane {
    let terminal: LocalProcessTerminalView

    /// Focus target for the window's `⌃⌘+hjkl` focus manager.
    var focusView: NSView { terminal }

    /// Called when the hosted process exits, so the host can decide what to do
    /// (e.g. respawn the shell, or mark the agent pane idle).
    var onProcessTerminated: ((Int32?) -> Void)?

    /// - Parameter deguttersCopy: use the agent-pane view that strips Claude's gutter
    ///   from copied text. Off for the shell (its copy is already truthful).
    init(deguttersCopy: Bool = false) {
        terminal = deguttersCopy ? AgentTerminalView(frame: .zero) : LocalProcessTerminalView(frame: .zero)
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyTheme() {
        terminal.installColors(Theme.ansi)
        terminal.nativeBackgroundColor = NSColor(swiftTerm: Theme.terminalBackground)
        terminal.nativeForegroundColor = NSColor(swiftTerm: Theme.terminalForeground)
        terminal.caretColor = NSColor(swiftTerm: Theme.terminalCursor)
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
