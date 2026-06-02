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

/// One notification request. `kind` distinguishes the agent lifecycle event so the
/// app can choose copy, sound, and (later) a click action per event.
public struct NotifyMessage: Codable {
    public enum Kind: String, Codable {
        case stop          // agent finished a turn
        case inputNeeded   // agent is waiting on the user
    }

    public let kind: Kind
    public let title: String
    public let body: String

    public init(kind: Kind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }

    /// Encode as a single newline-terminated JSON line for the stream protocol.
    public func encodedLine() -> Data {
        var data = (try? JSONEncoder().encode(self)) ?? Data()
        data.append(0x0A) // '\n'
        return data
    }
}
