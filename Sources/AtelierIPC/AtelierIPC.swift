import Foundation

/// The IPC contract shared by the app (listener) and the `atelier-notify` CLI
/// (sender). A unix domain socket carries newline-delimited JSON `NotifyMessage`s.
public enum AtelierIPC {
    /// Where Atelier keeps runtime state — the socket, the persisted session
    /// tree. Mirrors the dotfiles `~/.local/state/...` convention. Dev-only:
    /// `ATELIER_STATE_DIR` relocates it so a test build can run beside the
    /// live app without contending for its socket or clobbering its session
    /// file; the hook CLI inherits the variable through Claude's environment,
    /// so notifications from the test instance's sessions land in the test
    /// instance.
    public static func stateDirectory() -> String {
        if let override = ProcessInfo.processInfo.environment["ATELIER_STATE_DIR"], !override.isEmpty {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/state/atelier"
    }

    /// Stable per-user socket path, inside `stateDirectory()`.
    public static func socketPath() -> String {
        "\(stateDirectory())/notify.sock"
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
        case inputNeeded   // `idle_prompt`: a minute after a turn ends, the agent still idles (never news)
        case blocked       // agent explicitly blocked: permission or question (the `!`)
        case working       // agent began a turn (tab state only, no banner)
        case session       // a conversation began under the agent: launch, /resume, /clear (tab state only)
    }

    public let kind: Kind
    public let title: String
    public let body: String
    public let sessionId: String?
    /// The Atelier tab whose Claude fired the hook — `ATELIER_TAB`, set on
    /// every agent Atelier spawns and inherited by its hooks. It outlives
    /// the conversation: `/resume` or `/clear` inside Claude switch
    /// `sessionId`, never this. Absent from older helpers and from agents
    /// started outside Atelier.
    public let tab: String?
    /// How a `.session` began — SessionStart's `source`: `startup`, `resume`,
    /// `clear` or `compact`. It decides the tab's dot: an empty conversation
    /// (startup, clear) is grey, a resumed one is your move, a compaction
    /// changes nothing. Absent from older helpers.
    public let source: String?
    /// On a `.stop`: the background agents and workflows Claude left running
    /// when its turn ended. It wakes itself when they finish, so the turn's
    /// end isn't the work's end. From Stop's `background_tasks`, filtered by
    /// the helper. Absent when there are none, and from older helpers.
    public let pending: [PendingWork]?

    /// One piece of background work Claude is waiting on.
    public struct PendingWork: Codable, Equatable {
        public enum Kind: String, Codable { case agent, workflow }
        public let kind: Kind
        /// The task's description, or a workflow's name.
        public let name: String

        public init(kind: Kind, name: String) {
            self.kind = kind
            self.name = name
        }
    }

    /// The environment variable that carries `tab` from agent to hook.
    public static let tabEnvironmentKey = "ATELIER_TAB"

    public init(kind: Kind, title: String, body: String, sessionId: String? = nil, tab: String? = nil, source: String? = nil,
                pending: [PendingWork]? = nil) {
        self.kind = kind
        self.title = title
        self.body = body
        self.sessionId = sessionId
        self.tab = tab
        self.source = source
        self.pending = pending
    }

    /// What Claude is waiting on, from a Stop hook payload's
    /// `background_tasks`: its background agents and workflows — the work
    /// its own "Waiting for N background agents…" line counts, and what
    /// wakes it when done. Claude labels each entry by type: `subagent`,
    /// `workflow`, `shell`, `monitor`, `teammate`, `cloud session`… Shells and
    /// monitors are left out because a dev server or a watcher never ends.
    /// Teammates and cloud sessions are left out because Claude stops
    /// counting them while they idle or run long, and the payload doesn't
    /// say which. Paused work isn't waited on. Names are kept short: the
    /// socket reads one 4 KB line.
    public static func pendingWork(fromStopPayload payload: [String: Any]) -> [PendingWork] {
        let tasks = payload["background_tasks"] as? [[String: Any]] ?? []
        var work: [PendingWork] = []
        for task in tasks where (task["status"] as? String) != "paused" {
            let kind: PendingWork.Kind
            let name: String?
            switch task["type"] as? String {
            case "subagent":
                kind = .agent
                name = task["description"] as? String
            case "workflow":
                kind = .workflow
                name = (task["name"] as? String) ?? (task["description"] as? String)
            default:
                continue
            }
            var short = (name ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            if short.count > 60 { short = String(short.prefix(59)) + "…" }
            work.append(PendingWork(kind: kind, name: short))
            if work.count == 16 { break }
        }
        return work
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
        case lspProbe // run go-to-definition at line/column in the active editor; dump to `path`
        case seedAttention // give the active project one session per attention state (dev)
        case toggleExplorer // ⌘B over the socket, for snapshots of the tree (dev)
        case explorerSearch // type `path` into the explorer's search bar (dev)
    }

    public let debug: Action
    /// Output directory for snapshots / output file for probe dumps.
    public let path: String
    /// lspProbe: 1-based caret to query.
    public let line: Int?
    public let column: Int?

    public init(debug: Action, path: String, line: Int? = nil, column: Int? = nil) {
        self.debug = debug
        self.path = path
        self.line = line
        self.column = column
    }
}

extension AtelierIPC {
    /// Connect to the app's socket and write one message line. Returns false if
    /// the app isn't listening (callers decide whether to launch it and retry).
    public static func send(line: Data) -> Bool {
        guard let fd = connectToApp() else { return false }
        defer { close(fd) }
        let written = line.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, raw.count)
        }
        return written == line.count
    }

    /// Whether an Atelier already answers on this state directory's socket.
    /// The app asks before it binds: a second instance on one directory
    /// would take the first one's hooks and resume its conversations twice.
    public static func isAppListening() -> Bool {
        guard let fd = connectToApp() else { return false }
        close(fd)
        return true
    }

    /// A socket connected to the app, or nil if nothing is listening.
    private static func connectToApp() -> Int32? {
        let path = socketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
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
        guard connected == 0 else { close(fd); return nil }
        return fd
    }
}
