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
        guard let path = transcriptPath(sessionId: sessionId, cwd: cwd),
              let data = FileManager.default.contents(atPath: path),
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

    /// Where Claude keeps the transcript. Claude Code names the project
    /// directory by replacing every character outside `[A-Za-z0-9]` with `-`
    /// (`/Users/core/.local/share/worktrees/BCI_HW1/jashd` →
    /// `-Users-core--local-share-worktrees-BCI-HW1-jashd`); an earlier reader
    /// only swapped `/` and `.`, so repos with an underscore never titled
    /// (owner report 2026-09-08). If the encoding drifts again, fall back to
    /// finding the file by its session id — the id is unique per transcript.
    static func transcriptPath(sessionId: String, cwd: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projects = "\(home)/.claude/projects"
        let encoded = String(cwd.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII ? Character(scalar) : "-"
        })
        let expected = "\(projects)/\(encoded)/\(sessionId).jsonl"
        if FileManager.default.fileExists(atPath: expected) { return expected }
        if let cached = resolved[sessionId] { return cached }
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projects) else { return nil }
        for dir in dirs {
            let candidate = "\(projects)/\(dir)/\(sessionId).jsonl"
            if FileManager.default.fileExists(atPath: candidate) {
                resolved[sessionId] = candidate
                return candidate
            }
        }
        return nil
    }

    /// Fallback lookups, remembered per session id (the scan touches every
    /// project directory and this runs on a 2 s timer).
    nonisolated(unsafe) private static var resolved: [String: String] = [:]

    private static func firstLine(_ s: String) -> String {
        s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? s
    }
}
