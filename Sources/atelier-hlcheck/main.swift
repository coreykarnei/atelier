import Foundation
import CodeEditLanguages
import CodeEditSourceEditor
import SwiftTreeSitter

// atelier-hlcheck <file> [--lang <id>] [--summary]
//
// Compiles the language's highlight query exactly the way the editor does
// (parent + additional query files combined, against the bundled grammar),
// parses the file, runs the query with predicates resolved, and prints one
// line per capture *after* the editor's own resolution rule (lowest capture
// index wins a range). A capture the theme can't place ("→ plain") is the
// thing to fix in the query or in CaptureName.fromString.

var file: String?
var langID: String?
var summaryOnly = false
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let arg = iterator.next() {
    switch arg {
    case "--lang": langID = iterator.next()
    case "--summary": summaryOnly = true
    default: file = arg
    }
}
guard let file else {
    FileHandle.standardError.write("usage: atelier-hlcheck <file> [--lang <id>] [--summary]\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: file)
guard let text = try? String(contentsOf: url, encoding: .utf8) else {
    FileHandle.standardError.write("cannot read \(file)\n".data(using: .utf8)!); exit(2)
}

let language: CodeLanguage
if let langID {
    guard let found = CodeLanguage.allLanguages.first(where: { $0.id.rawValue == langID }) else {
        FileHandle.standardError.write("unknown language id '\(langID)'. Known: \(CodeLanguage.allLanguages.map { $0.id.rawValue }.sorted().joined(separator: " "))\n".data(using: .utf8)!)
        exit(2)
    }
    language = found
} else {
    language = CodeLanguage.detectLanguageFrom(url: url)
}
print("language: \(language.id.rawValue) (tree-sitter-\(language.tsName))")
guard let tsLanguage = language.language else { print("no grammar bundled"); exit(1) }
guard let queryURL = language.queryURL else { print("no highlights.scm"); exit(1) }

// Same combination rule as CodeEditLanguages.TreeSitterModel.queryFor.
var queryURLs: [URL] = []
if let parent = language.parentQueryURL {
    queryURLs = [queryURL, parent]
} else if let additional = language.additionalHighlights {
    queryURLs = additional.sorted().map { queryURL.deletingLastPathComponent().appendingPathComponent("\($0).scm") } + [queryURL]
} else {
    queryURLs = [queryURL]
}
var sources: [(URL, String)] = []
for u in queryURLs {
    if let s = try? String(contentsOf: u, encoding: .utf8) { sources.append((u, s)) }
    else { print("warning: missing query file \(u.path)") }
}
let combined = sources.map { $0.1 }.joined(separator: "\n")
print("query files: " + sources.map { $0.0.lastPathComponent + " (\($0.1.count) chars)" }.joined(separator: ", "))

let query: Query
do {
    query = try Query(language: tsLanguage, data: combined.data(using: .utf8)!)
} catch let error as QueryError {
    // Point at the offending line of the *combined* text.
    func describe(_ offset: UInt32) -> String {
        let bytes = Array(combined.utf8)
        let clamped = min(Int(offset), max(0, bytes.count - 1))
        let before = String(decoding: bytes[0..<clamped], as: UTF8.self)
        let lineNumber = before.split(separator: "\n", omittingEmptySubsequences: false).count
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        let lineText = lineNumber - 1 < lines.count ? String(lines[lineNumber - 1]) : ""
        return "line \(lineNumber): \(lineText.trimmingCharacters(in: .whitespaces))"
    }
    let kind: String
    let offset: UInt32
    switch error {
    case .syntax(let o): kind = "syntax"; offset = o
    case .nodeType(let o): kind = "unknown node type"; offset = o
    case .field(let o): kind = "unknown field"; offset = o
    case .capture(let o): kind = "bad capture"; offset = o
    case .structure(let o): kind = "structure"; offset = o
    case .unknown(let o): kind = "unknown"; offset = o
    case .none: kind = "none"; offset = 0
    @unknown default: kind = "?"; offset = 0
    }
    print("QUERY FAILED (\(kind)) at \(describe(offset))")
    print("The editor would silently show this language unhighlighted.")
    exit(1)
} catch {
    print("QUERY FAILED: \(error)"); exit(1)
}

let parser = Parser()
try parser.setLanguage(tsLanguage)
guard let tree = parser.parse(text), let root = tree.rootNode else { print("parse failed"); exit(1) }
let ns = text as NSString
let cursor = query.execute(node: root, in: tree)
let provider: SwiftTreeSitter.Predicate.TextProvider = { range, _ in
    NSMaxRange(range) <= ns.length ? ns.substring(with: range) : nil
}

// The editor's rule (TreeSitterClient+Highlight.swift): names the theme can't
// place are dropped FIRST, then one capture per range — lowest capture index
// wins, and that index is the capture *name's* first appearance in the query.
var best: [NSRange: (index: Int, name: String)] = [:]
var unmappedSeen: [String: Int] = [:]
for match in cursor.resolve(with: .init(textProvider: provider)) {
    for capture in match.captures {
        guard let name = capture.name else { continue }
        guard CaptureName.fromString(name) != nil else { unmappedSeen[name, default: 0] += 1; continue }
        let range = capture.range
        if let existing = best[range], existing.index <= capture.index { continue }
        best[range] = (capture.index, name)
    }
}
let ordered = best.sorted { $0.key.location != $1.key.location ? $0.key.location < $1.key.location : $0.key.length > $1.key.length }

func lineColumn(_ location: Int) -> (Int, Int) {
    let prefix = ns.substring(to: min(location, ns.length))
    let lines = prefix.components(separatedBy: "\n")
    return (lines.count, (lines.last?.count ?? 0) + 1)
}

var counts: [String: Int] = [:]
var unmapped: Set<String> = []
for (range, value) in ordered {
    counts[value.name, default: 0] += 1
    let mapped = CaptureName.fromString(value.name)
    if mapped == nil { unmapped.insert(value.name) }
    if !summaryOnly {
        let (line, column) = lineColumn(range.location)
        var snippet = NSMaxRange(range) <= ns.length ? ns.substring(with: range) : "<out of range>"
        snippet = snippet.replacingOccurrences(of: "\n", with: "⏎")
        if snippet.count > 40 { snippet = String(snippet.prefix(40)) + "…" }
        let target = mapped.map { "→ \($0)" } ?? "→ plain"
        print(String(format: "%4d:%-3d %-28@ %-22@ %@", line, column, value.name, target, snippet))
    }
}
print("")
print("captures (\(ordered.count) spans):")
for (name, count) in counts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
    let mapped = CaptureName.fromString(name).map { "→ \($0)" } ?? "→ PLAIN"
    print(String(format: "  %-28@ %5d  %@", name, count, mapped))
}
if !unmappedSeen.isEmpty {
    print("skipped captures (no theme slot; the editor ignores them, other captures on the same range still paint): "
        + unmappedSeen.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: ", "))
}
if language.additionalHighlights?.contains("injections") == true {
    print("note: this language injects others (e.g. markdown → markdown-inline); injected regions are not run here.")
}
