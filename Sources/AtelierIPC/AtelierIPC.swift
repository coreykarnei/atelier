import Foundation

/// The IPC contract shared by the app (listener) and the `atelier-notify` CLI
/// (sender). A unix domain socket carries newline-delimited JSON `NotifyMessage`s.
public enum AtelierIPC {
    /// Stable per-user socket path. Mirrors the dotfiles `~/.local/state/...`
    /// convention so it sits with other Atelier runtime state.
    public static func socketPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/state/atelier/notify.sock"
    }

    /// Ensure the parent directory exists. Returns the socket path.
    @discardableResult
    public static func ensureSocketDirectory() -> String {
        let path = socketPath()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return path
    }
}

/// One agent lifecycle event. `kind` distinguishes the event so the app can choose
/// copy, sound, tab badge, and click action per event. `sessionId` (Claude's own
/// session id, from the hook's stdin payload) lets the app badge and focus the
/// exact session tab that fired.
public struct NotifyMessage: Codable {
    public enum Kind: String, Codable {
        case stop          // agent finished a turn
        case inputNeeded   // agent is waiting on the user
        case working       // agent began a turn (tab state only, no banner)
    }

    public let kind: Kind
    public let title: String
    public let body: String
    public let sessionId: String?

    public init(kind: Kind, title: String, body: String, sessionId: String? = nil) {
        self.kind = kind
        self.title = title
        self.body = body
        self.sessionId = sessionId
    }

    /// Encode as a single newline-terminated JSON line for the stream protocol.
    public func encodedLine() -> Data {
        var data = (try? JSONEncoder().encode(self)) ?? Data()
        data.append(0x0A) // '\n'
        return data
    }
}

/// One workspace command from the `atelier` CLI (MILESTONE_1 §6) — the native
/// successor of the `ide` script's verbs. Shares the socket with notifications;
/// the listener tells the two message shapes apart by their keys.
public struct CommandMessage: Codable {
    public enum Verb: String, Codable {
        case open           // atelier [path]      → focus/open the project for path
        case worktreeAdd    // atelier -b <branch> → create/reuse worktree + session
        case worktreeRemove // atelier -rm <branch>
    }

    public let verb: Verb
    /// Absolute path the CLI was aimed at (its $PWD or the positional arg).
    public let path: String
    public let branch: String?

    public init(verb: Verb, path: String, branch: String? = nil) {
        self.verb = verb
        self.path = path
        self.branch = branch
    }

    public func encodedLine() -> Data {
        var data = (try? JSONEncoder().encode(self)) ?? Data()
        data.append(0x0A)
        return data
    }
}

/// Dev-only plumbing: debug commands for the polish pass's visual feedback
/// loop. `snapshot` makes the app write PNGs of its own windows (self-capture
/// needs no Screen Recording grant, unlike `screencapture`). Not surfaced in
/// the `atelier` CLI — send raw JSON at the socket.
public struct DebugMessage: Codable {
    public enum Action: String, Codable {
        case snapshot // write a PNG per visible window into `path`
    }

    public let debug: Action
    /// Output directory for snapshots.
    public let path: String

    public init(debug: Action, path: String) {
        self.debug = debug
        self.path = path
    }
}

extension AtelierIPC {
    /// Connect to the app's socket and write one message line. Returns false if
    /// the app isn't listening (callers decide whether to launch it and retry).
    public static func send(line: Data) -> Bool {
        let path = socketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[bytes.count] = 0
            }
        }
        let connected = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                connect(fd, sp, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }
        let written = line.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, raw.count)
        }
        return written == line.count
    }
}
