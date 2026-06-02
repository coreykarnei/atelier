import Foundation

/// Recovers the *logical markdown* behind a rendered agent-pane selection.
///
/// Claude Code's Ink TUI hard-wraps and gutters its text into the terminal grid, so
/// a selection copies fragmented, indented rows. The logical source still exists in
/// Claude's own transcript (`~/.claude/projects/<cwd>/<session>.jsonl`). We align the
/// selection to that source and return the exact markdown slice.
///
/// The alignment trick: markdown markup almost never changes the *letters* a reader
/// sees (`**bold**`→`bold`, `` `code` ``→`code`, `# H`→`H`). So we reduce both the
/// selection and each transcript message to a bare letters/digits stream, find the
/// selection inside a message, and map the match back to source offsets. Markdown
/// link targets and code-fence language tags carry letters that are *not* on screen,
/// so we drop those while reducing.
///
/// Reading the transcript is permitted under the (relaxed) TECHNICAL_PLAN §2.2: we
/// read Claude's persisted output, we do not parse its live UI / terminal stream.
enum TranscriptCopy {
    /// Minimum reduced-needle length to attempt a match — short selections are
    /// ambiguous and better served by the literal-copy fallback.
    static let minNeedle = 12

    /// Best-effort: clean markdown for `selection`, or nil to fall back to literal copy.
    static func markdown(forSelection selection: String, cwd: String) -> String? {
        let (needle, _) = reduce(Array(selection))
        guard needle.count >= minNeedle else { return nil }
        guard let path = locateTranscript(cwd: cwd) else { return nil }
        // Most-recent message first: resolves duplicate phrasings toward what's on screen.
        for message in assistantMessages(fromTranscriptAt: path).reversed() {
            if let slice = align(needle: needle, message: Array(message)) {
                return slice
            }
        }
        return nil
    }

    // MARK: Reduction

    /// Reduce a character array to a lowercase letters/digits stream plus a map from
    /// each reduced position back to its index in the input array.
    static func reduce(_ chars: [Character]) -> (reduced: String, map: [Int]) {
        var reduced: [Character] = []
        var map: [Int] = []
        var i = 0
        let n = chars.count
        var atLineStart = true

        while i < n {
            let c = chars[i]

            // Code-fence marker line (``` or ```lang): skip the whole line — neither
            // the backticks nor the language tag appear as on-screen text.
            if atLineStart, c == "`", i + 2 < n, chars[i + 1] == "`", chars[i + 2] == "`" {
                while i < n, chars[i] != "\n" { i += 1 }
                atLineStart = false
                continue
            }

            // Markdown link target `](url)`: keep the display text, drop the URL.
            if c == "]", i + 1 < n, chars[i + 1] == "(" {
                i += 2
                while i < n, chars[i] != ")" { i += 1 }
                if i < n { i += 1 } // consume ')'
                atLineStart = false
                continue
            }

            if c == "\n" {
                atLineStart = true
                i += 1
                continue
            }
            atLineStart = false

            if c.isLetter || c.isNumber {
                reduced.append(contentsOf: c.lowercased())
                // One source index per reduced unit; lowercasing a single letter is
                // single-unit in practice, so map the whole run to this index.
                while map.count < reduced.count { map.append(i) }
            }
            i += 1
        }
        return (String(reduced), map)
    }

    /// Find `needle` (an already-reduced stream) inside `message` and return the raw
    /// markdown slice spanning the match.
    static func align(needle: String, message: [Character]) -> String? {
        let (reduced, map) = reduce(message)
        guard !reduced.isEmpty, let range = reduced.range(of: needle) else { return nil }
        let start = reduced.distance(from: reduced.startIndex, to: range.lowerBound)
        let end = reduced.distance(from: reduced.startIndex, to: range.upperBound) - 1
        guard start >= 0, end >= start, end < map.count else { return nil }
        return String(message[map[start]...map[end]])
    }

    // MARK: Transcript IO

    /// Locate the newest session transcript for `cwd`. Claude encodes the project dir
    /// by replacing `/` and `.` with `-`.
    static func locateTranscript(cwd: String) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let encoded = cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let dir = "\(home)/.claude/projects/\(encoded)"
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        let transcripts = files.filter { $0.hasSuffix(".jsonl") }.map { "\(dir)/\($0)" }
        return transcripts.max { a, b in
            let da = (try? fm.attributesOfItem(atPath: a)[.modificationDate]) as? Date ?? .distantPast
            let db = (try? fm.attributesOfItem(atPath: b)[.modificationDate]) as? Date ?? .distantPast
            return da < db
        }
    }

    /// Raw markdown of each assistant message, in file order. Concatenates the text
    /// blocks within a message; ignores thinking / tool blocks and non-assistant rows.
    static func assistantMessages(fromTranscriptAt path: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return [] }
        var messages: [String] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { continue }
            var text = ""
            for block in blocks where block["type"] as? String == "text" {
                if let t = block["text"] as? String { text += t }
            }
            if !text.isEmpty { messages.append(text) }
        }
        return messages
    }
}
