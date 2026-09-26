import Foundation
import AtelierIPC

/// The Claude Code hooks Atelier hands every agent it spawns (2026-09-26,
/// owner call: a host shouldn't need its guest's config edited). They ride
/// `claude --settings <json>`, which Claude merges into the user's own
/// settings for that one process — verified: both sets fire, and a command
/// that appears in both runs once. So nothing is merged into
/// `~/.claude/settings.json`, a `claude` in a plain terminal fires none of
/// them, and the helper they name is always the one in this bundle —
/// never an older copy that would read a newer verb as `stop`.
///
/// Remote agents still get theirs from `provision.sh`: the helper there is
/// the host's python one.
enum AgentHooks {
    /// The helper beside the app's executable (`bundle.sh` puts it there).
    /// Nil under a bare `swift run`, where the agent simply runs unhooked.
    private static var helperPath: String? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let path = dir.appendingPathComponent("atelier-notify").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// `--settings <json>` for a local agent, or nothing without a helper.
    static var launchArguments: [String] {
        guard let json = settingsJSON else { return [] }
        return ["--settings", json]
    }

    private static let settingsJSON: String? = {
        guard let helper = helperPath else { return nil }
        // Unquoted when it can be: a command string identical to one the
        // user merged by hand under the old setup dedupes against it.
        let safe = helper.allSatisfy { $0.isLetter || $0.isNumber || "/._-".contains($0) }
        let exe = safe ? helper : "'\(helper.replacingOccurrences(of: "'", with: "'\\''"))'"
        func entry(_ verb: String, matcher: String? = nil) -> [String: Any] {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": "\(exe) \(verb)"]]]
            if let matcher { entry["matcher"] = matcher }
            return entry
        }
        let hooks: [String: Any] = [
            "Stop": [entry("stop")],
            "Notification": [
                entry("blocked", matcher: "permission_prompt"),
                entry("waiting", matcher: "idle_prompt"),
            ],
            "UserPromptSubmit": [entry("working")],
            "PostToolUse": [entry("tool")],
            "PostToolUseFailure": [entry("tool")],
            "SessionStart": [entry("session")],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }()

    // MARK: The user's own sound hooks

    /// Sound-making hook commands in the user's Claude settings that will
    /// also fire under Atelier — on the events Atelier sounds for (Stop,
    /// Notification) — so the app can stay quiet rather than ring twice. A
    /// hook that checks `ATELIER_TAB` (`[ -n "$ATELIER_TAB" ] || afplay …`)
    /// has stepped aside and doesn't count. Re-read only when the file
    /// changes; this runs on every event.
    static func userSoundHooks() -> [String] {
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/settings.json"
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        if let cached = soundCache, cached.modified == modified { return cached.commands }
        let commands = modified == nil ? [] : scanSoundHooks(at: path)
        soundCache = (modified, commands)
        return commands
    }

    nonisolated(unsafe) private static var soundCache: (modified: Date?, commands: [String])?

    private static let soundMarkers = ["afplay", "\\a", "\\007", "say ", "osascript -e 'beep", "tput bel"]

    private static func scanSoundHooks(at path: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: path),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any] else { return [] }
        var found: [String] = []
        for event in ["Stop", "Notification"] {
            for entry in hooks[event] as? [[String: Any]] ?? [] {
                for hook in entry["hooks"] as? [[String: Any]] ?? [] {
                    guard let command = hook["command"] as? String,
                          !command.contains(NotifyMessage.tabEnvironmentKey),
                          soundMarkers.contains(where: command.contains) else { continue }
                    found.append(command)
                }
            }
        }
        return found
    }
}
