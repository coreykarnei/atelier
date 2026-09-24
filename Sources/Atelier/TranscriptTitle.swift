import Foundation

/// Reads a session's tab title from its Claude transcript — the same `ai-title`
/// that `/resume` shows (MILESTONE_1 §7). Because each session pins its own
/// `claudeSessionId`, we read *exactly* that transcript file, so titles never
/// collide across sessions sharing a cwd.
///
/// Permitted under the relaxed TECHNICAL_PLAN §2.2: we read Claude's persisted
/// output, not its live UI.
///
/// Incremental since 2026-09-16 (owner report: the Claude pane juddered for
/// ¼–½ s every couple of seconds). The 2 s poll used to read every session's
/// whole transcript and JSON-parse every line on the main thread; a day's
/// transcripts run to 50 MB, so each tick froze the UI. Now each transcript
/// is read once from where the last read stopped, only lines that can carry
/// a title are parsed, and all of it happens on a utility queue — the main
/// thread only ever receives the resolved strings.
enum TranscriptTitle {
    /// What we know about one transcript: how far we've read and the best
    /// title so far. Touched on `queue` only.
    private struct Progress {
        var path: String
        var offset: UInt64 = 0
        var aiTitle: String?
        var lastPrompt: String?
        var title: String? { aiTitle ?? lastPrompt.map(firstLine) }
        /// The conversation's last turn record is Claude's interrupt marker:
        /// Esc/⌃C ended the turn. No hook reports that — `Stop` is documented
        /// not to fire on a user interrupt — so this is the only word of it.
        var endsInterrupted = false
    }

    /// One tick's news for a session: its title, and whether the
    /// conversation came to rest on an interrupt since the last read.
    struct Reading {
        var title: String?
        var interrupted = false
    }

    nonisolated(unsafe) private static var progress: [String: Progress] = [:]
    private static let queue = DispatchQueue(label: "dev.sterlingcore.atelier.transcript-title", qos: .utility)

    /// Resolve titles for `sessions` off the main thread; `completion` gets
    /// `sessionId → Reading` for every session with a transcript, on
    /// the main queue. Calls coalesce: a tick that arrives while the previous
    /// one is still reading is dropped, so a slow disk can't queue up work.
    static func titles(for sessions: [(id: String, cwd: String)], completion: @escaping ([String: Reading]) -> Void) {
        guard !inFlight else { return }
        inFlight = true
        queue.async {
            var result: [String: Reading] = [:]
            for session in sessions {
                if let reading = advance(sessionId: session.id, cwd: session.cwd) { result[session.id] = reading }
            }
            DispatchQueue.main.async {
                inFlight = false
                completion(result)
            }
        }
    }
    nonisolated(unsafe) private static var inFlight = false

    /// Synchronous, whole-file read — the restore path and tests. Prefer
    /// `titles(for:)` for anything periodic.
    static func title(sessionId: String, cwd: String) -> String? {
        queue.sync { advance(sessionId: sessionId, cwd: cwd)?.title }
    }

    /// Read whatever the transcript gained since last time and fold any
    /// title records in. A file that shrank (rewritten) starts over. An
    /// interrupt is news once: the read that finds the conversation newly
    /// resting on one.
    private static func advance(sessionId: String, cwd: String) -> Reading? {
        guard let path = transcriptPath(sessionId: sessionId, cwd: cwd) else { return nil }
        var state = progress[sessionId] ?? Progress(path: path)
        if state.path != path { state = Progress(path: path) }
        let wasInterrupted = state.endsInterrupted
        guard let handle = FileHandle(forReadingAtPath: path) else { return Reading(title: state.title) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset { state = Progress(path: path) }
        if size > state.offset {
            try? handle.seek(toOffset: state.offset)
            let data = (try? handle.readToEnd()) ?? Data()
            // Only complete lines: the last one may still be mid-write.
            let complete = data.lastIndex(of: 0x0A).map { data.prefix(through: $0) } ?? Data()
            scan(complete, into: &state)
            state.offset += UInt64(complete.count)
        }
        progress[sessionId] = state
        return Reading(title: state.title, interrupted: state.endsInterrupted && !wasInterrupted)
    }

    private static let aiTitleKey = Data("\"ai-title\"".utf8)
    private static let lastPromptKey = Data("\"last-prompt\"".utf8)
    private static let userKey = Data("\"type\":\"user\"".utf8)
    private static let assistantKey = Data("\"type\":\"assistant\"".utf8)
    private static let sidechainKey = Data("\"isSidechain\":true".utf8)
    private static let interruptKey = Data("[Request interrupted by user".utf8)

    /// Fold the title records in `data` (whole lines) into `state`. Lines are
    /// screened by a byte search before any JSON is parsed — the transcript
    /// is almost entirely conversation, and only two record types matter —
    /// plus, for the interrupt, whether each main-thread turn record is
    /// Claude's marker (`[Request interrupted by user]`, or `… for tool
    /// use]`), a user record whose whole content is that text. The marker is
    /// matched structurally: a tool result quoting it (a grep of a
    /// transcript) is not one.
    private static func scan(_ data: Data, into state: inout Progress) {
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            start = end == data.endIndex ? end : data.index(after: end)
            let isUser = line.range(of: userKey) != nil
            if (isUser || line.range(of: assistantKey) != nil), line.range(of: sidechainKey) == nil {
                state.endsInterrupted = isUser && line.range(of: interruptKey) != nil && isInterruptMarker(line)
                continue
            }
            let hasAiTitle = line.range(of: aiTitleKey) != nil
            guard hasAiTitle || line.range(of: lastPromptKey) != nil else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "ai-title": if let t = obj["aiTitle"] as? String, !t.isEmpty { state.aiTitle = t }
            case "last-prompt": if let p = obj["lastPrompt"] as? String, !p.isEmpty { state.lastPrompt = p }
            default: break
            }
        }
    }

    private static func isInterruptMarker(_ line: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { return false }
        let text: String?
        if let content = message["content"] as? String {
            text = content
        } else if let blocks = message["content"] as? [[String: Any]], blocks.count == 1,
                  blocks[0]["type"] as? String == "text" {
            text = blocks[0]["text"] as? String
        } else {
            text = nil
        }
        return text?.hasPrefix("[Request interrupted by user") == true
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
        resolvedLock.lock()
        let cached = resolved[sessionId]
        resolvedLock.unlock()
        if let cached { return cached }
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projects) else { return nil }
        for dir in dirs {
            let candidate = "\(projects)/\(dir)/\(sessionId).jsonl"
            if FileManager.default.fileExists(atPath: candidate) {
                resolvedLock.lock()
                resolved[sessionId] = candidate
                resolvedLock.unlock()
                return candidate
            }
        }
        return nil
    }

    /// Fallback lookups, remembered per session id (the scan touches every
    /// project directory and this runs on a 2 s timer). Read from the main
    /// thread (restore) and the title queue, hence the lock.
    nonisolated(unsafe) private static var resolved: [String: String] = [:]
    private static let resolvedLock = NSLock()

    private static func firstLine(_ s: String) -> String {
        s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? s
    }
}
