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
    var dividers: [String: Double]
    /// Editor buffer path (M2.1). Optional so pre-M2 snapshots still decode.
    var openFile: String?
    /// Read only, never written: remote sessions were removed in v1.5.0, and
    /// a snapshot or shelf entry from before can still hold one, its `cwd` a
    /// directory on the host. Kept so `loadable()` can leave such a session
    /// behind on load instead of restoring it as a local one.
    var remoteHost: String? = nil
    /// The tab's attention state at quit (`Session.Attention` raw value), so a
    /// relaunch shows what you hadn't seen yet. Optional: older snapshots.
    var attention: String? = nil
}

struct PersistedWindow: Codable {
    var sessions: [PersistedSession]
    var activeIndex: Int
    /// The folder the project was opened on (`ProjectController.projectRoot`)
    /// — its name, kept so a relaunch doesn't rename the project after
    /// whichever session comes back first. Nil for an unpromoted project,
    /// and in older snapshots.
    var root: String? = nil

    /// The window with only the sessions that can come back: not a remote
    /// one from before v1.5.0's removal of remote sessions, and not one
    /// whose conversation id isn't a UUID — the id becomes a claude argument
    /// and part of a transcript path, so a tampered or corrupt file must not
    /// carry anything else there. The active tab is found again by
    /// conversation (an index would land on a neighbour once an earlier tab
    /// is gone). Nil when nothing is left.
    func loadable() -> PersistedWindow? {
        func keeps(_ session: PersistedSession) -> Bool {
            session.remoteHost == nil && UUID(uuidString: session.claudeSessionId) != nil
        }
        guard !sessions.allSatisfy(keeps) else { return self }
        let active = sessions.indices.contains(activeIndex) ? sessions[activeIndex].claudeSessionId : nil
        var kept = self
        kept.sessions = sessions.filter(keeps)
        NSLog("Atelier: left \(sessions.count - kept.sessions.count) saved session(s) behind (remote, or no valid conversation id)")
        guard !kept.sessions.isEmpty else { return nil }
        kept.activeIndex = kept.sessions.firstIndex { $0.claudeSessionId == active }
            ?? min(activeIndex, kept.sessions.count - 1)
        return kept
    }
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
        guard let data = FileManager.default.contents(atPath: path),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return nil }
        // A window with nothing local left goes; the active one is found
        // again among those that stay.
        var windows: [PersistedWindow] = []
        var active = 0
        for (index, window) in state.windows.enumerated() {
            guard let kept = window.loadable() else { continue }
            if index <= state.activeWindow { active = windows.count }
            windows.append(kept)
        }
        return PersistedState(windows: windows, activeWindow: active)
    }

    static func save(_ state: PersistedState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        AtelierIPC.writeStateFile(data, to: path)
    }
}

/// Projects closed by hand, kept to come back to (2026-09-24, owner call):
/// closing a project shelves its session tree under the folder it was opened
/// on — the project's `projectRoot`, the same string the Landing offers —
/// and opening that place again from a
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
        guard let data = FileManager.default.contents(atPath: path),
              let shelf = try? decoder.decode([String: Entry].self, from: data) else { return [:] }
        // Remote projects (`ssh://host:dir` keys) and remote sessions inside
        // local ones are from before v1.5.0; the next write drops them.
        return shelf.compactMapValues { entry in
            guard let window = entry.window.loadable(), window.sessions.contains(where: \.isIDE) else { return nil }
            return Entry(window: window, shelvedAt: entry.shelvedAt)
        }.filter { !$0.key.hasPrefix("ssh://") }
    }

    private static func save(_ shelf: [String: Entry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(shelf) else { return }
        AtelierIPC.writeStateFile(data, to: path)
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
    /// back in (`Session.restoredAttention`, what the tab will wear) — the
    /// Landing row's dots.
    /// Most recently shelved first; one read per Landing refresh.
    static func marks() -> [(key: String, marks: [Session.Attention])] {
        load().sorted { $0.value.shelvedAt > $1.value.shelvedAt }.map { key, entry in
            (key, entry.window.sessions.filter(\.isIDE).map(Session.restoredAttention))
        }
    }
}
