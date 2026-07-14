import Darwin
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

/// A host + remote directory, and its `ssh://host:dir` string form — the id
/// the Landing's summon rows and the recents list carry for remote targets.
struct RemoteTarget: Equatable {
    let host: String
    let dir: String

    var id: String { "ssh://\(host):\(dir)" }

    static func parse(_ id: String) -> RemoteTarget? {
        guard id.hasPrefix("ssh://") else { return nil }
        let rest = id.dropFirst("ssh://".count)
        guard !rest.isEmpty else { return nil }
        guard let colon = rest.firstIndex(of: ":") else {
            return RemoteTarget(host: String(rest), dir: "~")
        }
        let host = String(rest[..<colon])
        let dir = String(rest[rest.index(after: colon)...])
        guard !host.isEmpty else { return nil }
        return RemoteTarget(host: host, dir: dir.isEmpty ? "~" : dir)
    }
}

/// Hosts from `~/.ssh/config` (plus one level of `Include`) — the Landing's
/// remote offer. Wildcard patterns are config plumbing, not destinations.
enum SSHConfigHosts {
    static func all() -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        collect(file: "\(home)/.ssh/config", into: &out, seen: &seen, includeDepth: 1)
        return out
    }

    private static func collect(
        file: String, into out: inout [String], seen: inout Set<String>, includeDepth: Int
    ) {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
                .flatMap { $0.split(separator: "\t", omittingEmptySubsequences: true) }
            guard let keyword = tokens.first?.lowercased() else { continue }

            if keyword == "host" {
                for token in tokens.dropFirst() {
                    let host = String(token)
                    guard !host.contains(where: { "*?!".contains($0) }),
                          seen.insert(host).inserted else { continue }
                    out.append(host)
                }
            } else if keyword == "include", includeDepth > 0 {
                for token in tokens.dropFirst() {
                    var pattern = String(token)
                    if pattern.hasPrefix("~") {
                        pattern = home + pattern.dropFirst()
                    } else if !pattern.hasPrefix("/") {
                        pattern = "\(home)/.ssh/\(pattern)"
                    }
                    for included in Self.glob(pattern) {
                        collect(file: included, into: &out, seen: &seen, includeDepth: includeDepth - 1)
                    }
                }
            }
        }
    }

    private static func glob(_ pattern: String) -> [String] {
        var g = glob_t()
        defer { globfree(&g) }
        guard Darwin.glob(pattern, 0, nil, &g) == 0 else { return [] }
        return (0..<Int(g.gl_matchc)).compactMap {
            g.gl_pathv[$0].flatMap { String(cString: $0) }
        }
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
    static let tmuxConfPath = "~/.config/atelier/tmux-v4.conf"
    private static let tmuxConfLines = [
        "set -g status off",
        "set -g escape-time 0",
        "set -g default-terminal \"xterm-256color\"",
        // Truecolor needs both halves (owner report 2026-07-14, "muted"):
        // Tc declares the *outer* terminal (SwiftTerm) RGB-capable so tmux
        // stops downsampling to the 256 palette on the way out…
        "set -ga terminal-overrides \",xterm-256color:Tc\"",
        // …and COLORTERM tells *inner* processes (claude's chalk/ink checks
        // it, SwiftTerm exports it locally) to emit 24-bit color at all.
        "set-environment -g COLORTERM truecolor",
        "set -g history-limit 10000",
        "set -g exit-empty on",
        // Claude Code asks for this on attach; SwiftTerm sends focus reports.
        "set -g focus-events on",
    ]

    /// Shared client options for every ssh we spawn.
    static var baseOptions: [String] {
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
        // Temp + mv, not a straight redirect: the two panes bootstrap
        // concurrently, and one truncating the conf while the other's tmux
        // (the server-start winner) is parsing it drops whichever lines were
        // mid-flight — observed as the Tc override alone missing. mv is
        // atomic; a reader holds the complete old inode or sees the complete
        // new file.
        var script = "mkdir -p ~/.config/atelier && { [ -f \(tmuxConfPath) ] || { printf '%s\\n' "
        script += tmuxConfLines.map(quoted).joined(separator: " ")
        script += " > \(tmuxConfPath).$$ && mv \(tmuxConfPath).$$ \(tmuxConfPath); }; }; exec tmux -f \(tmuxConfPath) -L atelier"
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
        try? sshProcess(host: host, command: kills + "; true").run()
    }

    /// A non-PTY ssh Process running `command` on `host`, output discarded.
    /// The caller may replace stdio and must `run()` it.
    static func sshProcess(host: String, command: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = baseOptions + [host, "--", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
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

/// One per remote host, app-global (mirrors `LSPRegistry`): owns the host's
/// one-time provisioning (the notify sender + hook entries land on the host,
/// idempotent, versioned by the marker in provision.sh) and the **notify
/// forward** — a dedicated `ssh -N -R` that surfaces the host's hook events on
/// the Mac's notify socket, so remote sessions get the same tab attention as
/// local ones. Dedicated, not piggybacked on a pane's ssh: two panes can't
/// both bind the remote socket, and a pane reconnect shouldn't drop the
/// attention channel. ControlMaster puts all of it on one TCP link anyway.
final class RemoteLink {
    private static var links: [String: RemoteLink] = [:]

    static func link(for host: String) -> RemoteLink {
        if let existing = links[host] { return existing }
        let link = RemoteLink(host: host)
        links[host] = link
        return link
    }

    static func terminateAll() {
        for link in links.values { link.terminate() }
        links.removeAll()
    }

    let host: String
    private var provisionAttempted = false
    private var forward: Process?
    /// True from the first startForward() until an `-N` is actually running —
    /// two panes spawn back-to-back, and the second's prep step must not
    /// `rm -f` a socket the first just bound.
    private var establishing = false
    private var tornDown = false

    private init(host: String) { self.host = host }

    /// Called on every remote pane spawn — including reattaches, so a forward
    /// that died with the same network event comes back with the panes.
    /// Cheap when everything is already up.
    func activate() {
        ensureProvisioned()
        ensureForward()
    }

    func terminate() {
        tornDown = true
        forward?.terminationHandler = nil
        forward?.terminate()
        forward = nil
    }

    // MARK: Provisioning

    /// Ship the notify sender + hook entries to the host (provision.sh does
    /// the work and self-short-circuits on its marker). Once per app run;
    /// fire-and-forget — hooks just stay silent until it lands.
    private func ensureProvisioned() {
        guard !provisionAttempted else { return }
        provisionAttempted = true
        guard
            let scriptURL = Bundle.main.url(forResource: "provision", withExtension: "sh", subdirectory: "remote"),
            let notifyURL = Bundle.main.url(forResource: "atelier-notify", withExtension: "py", subdirectory: "remote"),
            let script = try? String(contentsOf: scriptURL, encoding: .utf8),
            let notifySource = try? Data(contentsOf: notifyURL)
        else {
            NSLog("Atelier: remote provisioning resources missing from bundle")
            return
        }
        let process = RemoteCommand.sshProcess(host: host, command: script)
        let stdin = Pipe()
        process.standardInput = stdin
        process.terminationHandler = { [host] p in
            if p.terminationStatus != 0 {
                NSLog("Atelier: provisioning \(host) exited \(p.terminationStatus)")
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("Atelier: couldn't run provisioning ssh for \(host): \(error)")
            return
        }
        stdin.fileHandleForWriting.write(notifySource)
        try? stdin.fileHandleForWriting.close()
    }

    // MARK: Notify forward

    private func ensureForward() {
        guard !tornDown, !establishing, forward?.isRunning != true else { return }
        establishing = true
        startForward()
    }

    /// Single-flight token: every startForward() bumps it, and every async
    /// continuation (prep exit, forward exit, scheduled retry) checks it —
    /// a stale chain must never rm the socket a newer chain just bound, nor
    /// clobber its process reference. Two chains fighting over the one remote
    /// bind path is exactly how the forward wedges (observed: a leaked `-N`
    /// held the sshd-side listener registration and every new bind failed).
    private var generation = 0

    /// Two steps, every (re)start: resolve the remote `$HOME` and clear the
    /// stale forwarded socket (for `-R`, only *server-side*
    /// StreamLocalBindUnlink could do this — unlinking ourselves needs no
    /// sshd config), then hold the `-N -R` open until it dies.
    private func startForward() {
        generation += 1
        let gen = generation
        // A straggler from a previous attempt may hold the remote bind and
        // would fight the new one — kill it without triggering its handler.
        forward?.terminationHandler = nil
        forward?.terminate()
        forward = nil

        let prep = RemoteCommand.sshProcess(
            host: host,
            command: "mkdir -p ~/.local/state/atelier && rm -f ~/.local/state/atelier/notify.sock && printf %s \"$HOME\""
        )
        let out = Pipe()
        prep.standardOutput = out
        prep.terminationHandler = { [weak self] process in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                guard let self, !self.tornDown, gen == self.generation else { return }
                let home = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard process.terminationStatus == 0, !home.isEmpty else {
                    self.scheduleForwardRetry()
                    return
                }
                self.launchForward(remoteHome: home, generation: gen)
            }
        }
        do { try prep.run() } catch { scheduleForwardRetry() }
    }

    private func launchForward(remoteHome: String, generation gen: Int) {
        guard gen == generation else { return }
        let remoteSock = "\(remoteHome)/.local/state/atelier/notify.sock"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: RemoteCommand.sshPath)
        // Its own direct connection, NOT the ControlMaster: a remote
        // unix-socket forward requested through the mux reports success but
        // never binds (observed against OpenSSH 9.8), and the attention
        // channel shouldn't share fate with the master's ControlPersist
        // lifecycle anyway.
        process.arguments = [
            "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "ConnectTimeout=5",
            "-N", "-o", "ExitOnForwardFailure=yes",
            "-R", "\(remoteSock):\(AtelierIPC.socketPath())",
            host,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.tornDown, gen == self.generation else { return }
                self.forward = nil
                self.scheduleForwardRetry()
            }
        }
        forward = process
        do {
            try process.run()
            establishing = false
        } catch {
            forward = nil
            scheduleForwardRetry()
        }
    }

    /// Flat 5s retry, forever while the app runs — the forward should be up
    /// whenever the host is reachable, and quiet attempts are cheap.
    private func scheduleForwardRetry() {
        establishing = true
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.tornDown, gen == self.generation else { return }
            guard self.forward?.isRunning != true else {
                self.establishing = false
                return
            }
            self.startForward()
        }
    }
}
