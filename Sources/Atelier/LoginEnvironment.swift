import Foundation

/// The environment the owner's interactive login zsh builds — what Claude
/// sees when Ghostty launches it. A GUI app inherits launchd's bare
/// environment, and SwiftTerm's `getEnvironmentVariables` forwards only a
/// handful of names (PATH deliberately not among them), so a directly
/// spawned `claude` ran with no PATH: its Bash tool couldn't find `head`,
/// and MCP servers launched via `npx` failed ENOENT. Most of the PATH lives
/// in `.zshrc` (conda, homebrew, `~/.local/bin`), so the capture is `-lic`,
/// not just `-l`.
///
/// Captured once, off the main thread, starting at launch (`prefetch`) —
/// conda's hook makes it ~0.8s, which must not land on the first spawn.
enum LoginEnvironment {
    private static let marker = "__ATELIER_ENV__"
    private static let lock = NSLock()
    private static var captured: [String: String]?
    private static var inFlight: DispatchSemaphore?

    /// Shell bookkeeping and terminal fingerprints from the capture shell;
    /// the pane sets its own terminal identity.
    private static let dropped: Set<String> = [
        "SHLVL", "PWD", "OLDPWD", "_", "TERM", "COLORTERM",
        "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TMUX", "TMUX_PANE",
    ]

    static func prefetch() {
        lock.lock()
        defer { lock.unlock() }
        guard captured == nil, inFlight == nil else { return }
        let done = DispatchSemaphore(value: 0)
        inFlight = done
        DispatchQueue.global(qos: .userInitiated).async {
            let env = capture()
            lock.lock()
            captured = env
            inFlight = nil
            lock.unlock()
            done.signal()
        }
    }

    /// The captured environment, waiting (bounded) for a capture still in
    /// flight. Empty if the shell failed — callers fall back to their own.
    static func current() -> [String: String] {
        prefetch()
        lock.lock()
        if let captured { lock.unlock(); return captured }
        let pending = inFlight
        lock.unlock()
        _ = pending?.wait(timeout: .now() + 5)
        lock.lock()
        defer { lock.unlock() }
        return captured ?? [:]
    }

    /// `env` entries (`KEY=value`) for a spawned process: the login
    /// environment with `overrides` applied last.
    static func entries(overriding overrides: [String]) -> [String] {
        var env = current()
        if env["PATH"] == nil {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        for entry in overrides {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// Run the owner's shell interactively (so `.zshrc` runs) with stdin
    /// closed, print a marker past any startup chatter, then `env -0`.
    /// Killed after 10s so a `.zshrc` that waits on input can't hang this.
    private static func capture() -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "printf '\\0\(marker)\\0'; /usr/bin/env -0"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return [:] }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        guard let start = fields.firstIndex(of: marker) else { return [:] }
        var env: [String: String] = [:]
        for field in fields[(start + 1)...] {
            guard let eq = field.firstIndex(of: "="), eq != field.startIndex else { continue }
            let key = String(field[..<eq])
            guard !dropped.contains(key) else { continue }
            env[key] = String(field[field.index(after: eq)...])
        }
        return env
    }
}
