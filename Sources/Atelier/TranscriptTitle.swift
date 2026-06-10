import Foundation

/// Reads a session's tab title from its Claude transcript — the same `ai-title`
/// that `/resume` shows (MILESTONE_1 §7). Because each session pins its own
/// `claudeSessionId`, we read *exactly* that transcript file, so titles never
/// collide across sessions sharing a cwd.
///
/// Permitted under the relaxed TECHNICAL_PLAN §2.2: we read Claude's persisted
/// output, not its live UI.
enum TranscriptTitle {
    /// The best title for `sessionId` in `cwd`, or nil if the transcript has none
    /// yet (a fresh session). Prefers Claude's generated `ai-title`; falls back to
    /// the user's first prompt.
    static func title(sessionId: String, cwd: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let encoded = cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let path = "\(home)/.claude/projects/\(encoded)/\(sessionId).jsonl"

        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }

        var aiTitle: String?
        var lastPrompt: String?
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "ai-title": if let t = obj["aiTitle"] as? String, !t.isEmpty { aiTitle = t }
            case "last-prompt": if let p = obj["lastPrompt"] as? String, !p.isEmpty { lastPrompt = p }
            default: break
            }
        }
        return aiTitle ?? lastPrompt.map(firstLine)
    }

    private static func firstLine(_ s: String) -> String {
        s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? s
    }
}
