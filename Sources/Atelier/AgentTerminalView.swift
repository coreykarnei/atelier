import AppKit
import SwiftTerm

/// The agent pane's terminal view. Claude Code (an Ink TUI) lays out its text into
/// fixed-width rows and indents each one with a gutter under the message bullet —
/// so a plain copy drags that gutter along, which (among other things) corrupts the
/// indentation of any code you copy out.
///
/// We can't recover the agent's *logical line breaks* from the grid — those are gone
/// before the bytes reach the PTY (see the Milestone 0 spike finding). But the gutter
/// is a consistent leading-whitespace prefix, and stripping it is lossless and safe.
/// This is the in-bounds half of truthful agent-pane copy; the lossless rest needs a
/// transcript side-channel (a TECHNICAL_PLAN §2.2 decision).
final class AgentTerminalView: LocalProcessTerminalView {
    /// The agent process's working directory — used to locate Claude's transcript.
    var transcriptCwd: String?

    override func copy(_ sender: Any) {
        super.copy(sender) // SwiftTerm puts the raw selected text on the pasteboard
        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: .string) else { return }

        // Best path: recover the exact markdown source from Claude's transcript.
        if let cwd = transcriptCwd,
           let markdown = TranscriptCopy.markdown(forSelection: raw, cwd: cwd) {
            pb.clearContents()
            pb.setString(markdown, forType: .string)
            return
        }

        // Fallback: at least strip the gutter from the rendered selection.
        let cleaned = Self.stripCommonGutter(raw)
        guard cleaned != raw else { return }
        pb.clearContents()
        pb.setString(cleaned, forType: .string)
    }

    /// Remove the longest run of leading spaces shared by every non-blank line. This
    /// drops the agent's gutter while preserving *relative* indentation (nested code
    /// keeps its structure, since we only strip the common minimum).
    static func stripCommonGutter(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let leadingCounts = lines
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .map { $0.prefix { $0 == " " }.count }
        guard let common = leadingCounts.min(), common > 0 else { return text }
        return lines.map { line in
            line.allSatisfy(\.isWhitespace) ? line : String(line.dropFirst(common))
        }.joined(separator: "\n")
    }
}
