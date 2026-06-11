import Foundation

/// On-disk snapshot of the workspace (MILESTONE_1 §9): the window → session tree,
/// written when the app quits and restored on launch. Lives next to the socket in
/// `~/.local/state/atelier/`.
struct PersistedSession: Codable {
    var cwd: String
    var isIDE: Bool
    var layoutMode: String
    var title: String
    var customTitle: String?
    var claudeSessionId: String
    var dividers: [String: Double]
}

struct PersistedWindow: Codable {
    var sessions: [PersistedSession]
    var activeIndex: Int
}

struct PersistedState: Codable {
    var windows: [PersistedWindow]
    var activeWindow: Int
}

enum SessionStore {
    static var path: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/state/atelier/session.json"
    }

    static func load() -> PersistedState? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    static func save(_ state: PersistedState) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
