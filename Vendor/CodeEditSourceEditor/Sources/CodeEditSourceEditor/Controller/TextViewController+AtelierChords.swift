//
//  TextViewController+AtelierChords.swift
//  CodeEditSourceEditor (Atelier vendored copy)
//
//  The VSCode multi-cursor and line chords: ⌥⌘↑/↓ add a caret on the line
//  above/below, ⇧⌥↑/↓ duplicate the selected lines, ⌘D selects the next
//  occurrence of the selection (or the word at the caret). Wired from
//  `handleCommand`.
//

import AppKit
import CodeEditTextView

extension TextViewController {
    /// A caret on the neighbouring line at the same x for every selection.
    func addCursor(above: Bool) {
        let layoutManager = textView.layoutManager!
        var added: [NSRange] = []
        for selection in textView.selectionManager.textSelections {
            let offset = above ? selection.range.location : selection.range.max
            guard let rect = layoutManager.rectForOffset(offset) else { continue }
            let y = above ? rect.minY - rect.height / 2 : rect.maxY + rect.height / 2
            guard y >= 0, y <= layoutManager.estimatedHeight(),
                  let target = layoutManager.textOffsetAtPoint(CGPoint(x: rect.midX, y: y)) else { continue }
            added.append(NSRange(location: target, length: 0))
        }
        for range in added { textView.selectionManager.addSelectedRange(range) }
        textView.scrollSelectionToVisible()
    }

    /// Copy the lines under each selection and insert the copy above or
    /// below them. The caret lands on the copy so a second press keeps going.
    func duplicateLines(above: Bool) {
        guard !cursorPositions.isEmpty else { return }
        textView.undoManager?.beginUndoGrouping()
        textView.editSelections { textView, selection in
            guard let lines = getOverlappingLines(for: selection.range),
                  let first = textView.layoutManager.textLineForIndex(lines.lowerBound),
                  let last = textView.layoutManager.textLineForIndex(lines.upperBound) else { return }
            let block = NSRange(location: first.range.location, length: last.range.max - first.range.location)
            guard var text = textView.textStorage.substring(from: block) else { return }
            var insertAt = above ? block.location : block.max
            if !text.hasSuffix("\n") {
                // Last line of the document has no newline: the copy needs one
                // between the original and itself.
                if above { text += "\n" } else { text = "\n" + text; insertAt = block.max }
            }
            textView.replaceCharacters(in: [NSRange(location: insertAt, length: 0)], with: text)
            let copyStart = above ? block.location : (block.max + (text.hasPrefix("\n") ? 1 : 0))
            let copyLength = (text as NSString).length - (text.hasPrefix("\n") ? 1 : 0)
            let selectInCopy = NSRange(
                location: copyStart + (selection.range.location - block.location),
                length: min(selection.range.length, copyLength)
            )
            setCursorPositions([CursorPosition(range: selectInCopy)], scrollToVisible: true)
        }
        textView.undoManager?.endUndoGrouping()
    }

    /// ⌘D: with a selection, add the next match of its text as another
    /// selection (wrapping); with a bare caret, select the word first.
    func selectNextOccurrence() {
        let manager = textView.selectionManager!
        guard let last = manager.textSelections.last else { return }
        if last.range.isEmpty {
            textView.selectWord(nil)
            return
        }
        let storage = textView.textStorage.string as NSString
        guard let needle = textView.textStorage.substring(from: last.range), !needle.isEmpty else { return }
        let taken = Set(manager.textSelections.map(\.range.location))
        var searchFrom = last.range.max
        var found: NSRange?
        for _ in 0..<2 {
            let range = storage.range(of: needle, options: [], range: NSRange(location: searchFrom, length: storage.length - searchFrom))
            if range.location != NSNotFound, !taken.contains(range.location) {
                found = range
                break
            }
            searchFrom = 0 // wrap
        }
        guard let found else { return }
        manager.addSelectedRange(found)
        textView.scrollSelectionToVisible()
    }
}
