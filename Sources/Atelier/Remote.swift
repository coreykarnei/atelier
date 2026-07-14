import Foundation
import AtelierIPC

/// Where a session's hosted processes live. A remote session (VISION's `ide-pi`
/// successor) runs its shell and agent on another machine over ssh, wrapped in
/// host-side tmux so the *work* survives link death, laptop sleep, and app
/// quits — the Mac side only ever loses a disposable ssh client.
enum SessionLocation: Equatable {
    case local
    case remote(host: String)

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    var host: String? {
        if case .remote(let host) = self { return host }
        return nil
    }
}

/// Builds the ssh invocations for remote sessions. One option set everywhere:
/// ControlMaster so the panes (and later the notify forward) share a single
/// TCP link, ServerAlive so a dead link is *detected* in seconds instead of
/// hanging a pane for minutes.
enum RemoteCommand {
    static let sshPath = "/usr/bin/ssh"

    /// tmux runs on the *remote* under its own server (`-L atelier`) with its
    /// own conf — deterministic status-off/TERM without ever touching the
    /// host's tmux.conf. Versioned filename: changing the conf below must also
    /// bump the name so existing hosts rewrite it.
    static let tmuxConfPath = "~/.config/atelier/tmux-v2.conf"
    private static let tmuxConfLines = [
        "set -g status off",
        "set -g escape-time 0",
        "set -g default-terminal \"xterm-256color\"",
        "set -g history-limit 10000",
        "set -g exit-empty on",
        // Claude Code asks for this on attach; SwiftTerm sends focus reports.
        "set -g focus-events on",
    ]

    /// Shared client options for every ssh we spawn.
    private static var baseOptions: [String] {
        // Same state dir the notify socket lives in; %C keeps the path short.
        let stateDir = (AtelierIPC.ensureSocketDirectory() as NSString).deletingLastPathComponent
        return [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(stateDir)/cm-%C",
            "-o", "ControlPersist=60",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "ConnectTimeout=5",
        ]
    }

    /// POSIX single-quote escaping, used for every remote-shell word we build.
    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Remote dirs keep `~` semantics: the leading tilde must stay *unquoted*
    /// so the remote shell expands it; everything after it is quoted.
    private static func quotedRemoteDir(_ dir: String) -> String {
        if dir == "~" { return "~" }
        if dir.hasPrefix("~/") { return "~/" + quoted(String(dir.dropFirst(2))) }
        return quoted(dir)
    }

    /// The tmux session name for one pane of one Atelier session. Derived from
    /// the persisted `claudeSessionId` so a restored session reattaches to
    /// exactly its own tmux sessions.
    static func tmuxSessionName(claudeSessionId: String, pane suffix: String) -> String {
        "atelier-\(claudeSessionId.prefix(8))-\(suffix)"
    }

    /// argv for one remote pane: self-provision the tmux conf (idempotent,
    /// no ordering dependency on any separate setup step — a wiped host heals
    /// on the next spawn), then exec `tmux new-session -A`. `-A`'s semantics
    /// carry the whole reattach story: session alive → attach (the command is
    /// ignored, the running process is unharmed); session gone → create and
    /// run `command`.
    static func paneArgv(
        host: String, tmuxSession: String, remoteDir: String, command: String?
    ) -> [String] {
        var script = "mkdir -p ~/.config/atelier && { [ -f \(tmuxConfPath) ] || printf '%s\\n' "
        script += tmuxConfLines.map(quoted).joined(separator: " ")
        script += " > \(tmuxConfPath); }; exec tmux -f \(tmuxConfPath) -L atelier"
        script += " new-session -A -s \(tmuxSession) -c \(quotedRemoteDir(remoteDir))"
        if let command {
            script += " \(quoted(command))"
        }
        return baseOptions + ["-t", host, "--", script]
    }

    /// Tear down both of a session's tmux sessions on the host (⌘W — a
    /// deliberate close; app quit deliberately does *not* call this, so the
    /// work is still there to reattach to on relaunch). Fire-and-forget.
    static func killRemoteSessions(host: String, claudeSessionId: String) {
        let kills = ["sh", "ai"]
            .map { tmuxSessionName(claudeSessionId: claudeSessionId, pane: $0) }
            .map { "tmux -L atelier kill-session -t \(quoted($0)) 2>/dev/null" }
            .joined(separator: "; ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = baseOptions + [host, "--", kills + "; true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Interpret a pane's exit as link death (reattach) vs. a deliberate end
    /// (typed `exit`, tmux kill — the pane goes idle like a local shell's).
    /// ssh exits 255 on connection failure; SwiftTerm reports the raw waitpid
    /// status, so accept both encodings.
    static func isLinkFailure(_ exitCode: Int32?) -> Bool {
        guard let code = exitCode else { return false }
        if code == 255 { return true }
        return (code & 0x7f) == 0 && (code >> 8) & 0xff == 255
    }
}
