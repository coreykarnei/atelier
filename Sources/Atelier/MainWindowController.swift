import AppKit

/// The single Atelier window. For Milestone 0 (the spike) it hosts the two
/// terminal panes — shell on the left, agent (Claude Code) on the right — split
/// vertically. The fixed three-pane shape (editor top-left, shell bottom-left,
/// agent right) lands in Milestone 1; this is the stepping stone that proves the
/// native-terminal-ownership thesis.
final class MainWindowController: NSWindowController, NSSplitViewDelegate {
    private let shellPane = TerminalPane()
    private let agentPane = TerminalPane(deguttersCopy: true)

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

        buildLayout(in: blur)
    }

    private func buildLayout(in container: NSView) {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.translatesAutoresizingMaskIntoConstraints = false

        split.addArrangedSubview(shellPane)
        split.addArrangedSubview(agentPane)

        container.addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: container.topAnchor),
            split.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Agent column ~53% wide, mirroring the `ide` layout. User-resizable.
        DispatchQueue.main.async {
            split.setPosition(split.bounds.width * 0.47, ofDividerAt: 0)
        }
    }

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
    /// storm. Prefer the code root. (Milestone 1 replaces this with the selected
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

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 320)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - 320)
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
