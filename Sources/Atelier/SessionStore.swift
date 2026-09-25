import AtelierIPC
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
    /// Names the host-side tmux sessions when it differs from
    /// `claudeSessionId` (a new conversation started in the tab). Optional:
    /// absent means the two are the same, as in every older snapshot.
    var tmuxKey: String? = nil
    var dividers: [String: Double]
    /// Editor buffer path (M2.1). Optional so pre-M2 snapshots still decode.
    var openFile: String?
    /// Set for remote sessions: the ssh host; `cwd` is then the *remote* dir.
    /// Optional so pre-remote snapshots still decode.
    var remoteHost: String? = nil
    /// The tab's attention state at quit (`Session.Attention` raw value), so a
    /// relaunch shows what you hadn't seen yet. Optional: older snapshots.
    var attention: String? = nil
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
        "\(AtelierIPC.stateDirectory())/session.json"
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

/// Projects closed by hand, kept to come back to (2026-09-24, owner call):
/// closing a project shelves its session tree under the folder it was opened
/// on — the project's `projectRoot`, or a remote project's `ssh://host:dir`,
/// the same strings the Landing offers — and opening that place again from a
/// Landing restores the tree the way a relaunch would. `⌥`-close forgets
/// instead: the old "I'm done with this project". Its own file beside the
/// quit snapshot, so a quit neither drops the shelf nor restores it as tabs.
/// No expiry: an entry is a few hundred bytes, and the Landing says when one
/// is waiting.
enum ProjectShelf {
    struct Entry: Codable {
        var window: PersistedWindow
        var shelvedAt: Date
    }

    static var path: String {
        "\(AtelierIPC.stateDirectory())/shelf.json"
    }

    private static func load() -> [String: Entry] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        return (try? decoder.decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func save(_ shelf: [String: Entry]) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(shelf) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func put(_ key: String, _ window: PersistedWindow) {
        var shelf = load()
        shelf[key] = Entry(window: window, shelvedAt: Date())
        save(shelf)
    }

    /// Remove and return the entry — a shelved project comes back once.
    static func take(_ key: String) -> Entry? {
        var shelf = load()
        guard let entry = shelf.removeValue(forKey: key) else { return nil }
        save(shelf)
        return entry
    }

    static func forget(_ key: String) {
        var shelf = load()
        guard shelf.removeValue(forKey: key) != nil else { return }
        save(shelf)
    }

    /// The IDE sessions waiting under each key, as the state each will come
    /// back in (what `Session(restored:)` makes of it: an unseen completion
    /// stays unseen, any other turn is your move) — the Landing row's dots.
    /// Most recently shelved first; one read per Landing refresh.
    static func marks() -> [(key: String, marks: [Session.Attention])] {
        load().sorted { $0.value.shelvedAt > $1.value.shelvedAt }.map { key, entry in
            (key, entry.window.sessions.filter(\.isIDE).map { persisted in
                switch persisted.attention.flatMap(Session.Attention.init(rawValue:)) ?? .none {
                case .none: return .none
                case .doneUnseen: return .doneUnseen
                default: return .waiting
                }
            })
        }
    }
}
