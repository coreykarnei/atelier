import AppKit

/// `⌘⇧F` — repo-wide search (M2.3, TECHNICAL_PLAN §3.5). The third summon
/// card: here the query *produces* the offer instead of filtering it — each
/// keystroke (debounced ~150 ms) shells out to ripgrep (fixed-string,
/// smart-case; `git grep` when rg isn't installed), the matches are the rows,
/// and `↩` opens the hit in the buffer at its line and column. Keyboard-
/// navigable end to end; the fixed pane shape stays fixed — results live on
/// the card, not a fourth panel.
/// The repo text search engine, shared by ⌘⇧F and the explorer's search bar:
/// debounced (~150 ms) ripgrep — fixed-string, smart-case; `git grep` when rg
/// isn't installed — one process in flight, matches as summon rows, a capped
/// offer with an honest tail row.
final class RepoTextSearch {
    static let cap = 300
    static let moreRowId = "__more__"

    let root: String
    private var pendingSearch: DispatchWorkItem?
    private var runningProcess: Process?
    /// Serialized process bookkeeping (searches finish off-main).
    private let searchQueue = DispatchQueue(label: "atelier.repo-search")

    init(root: String) { self.root = root }

    deinit {
        pendingSearch?.cancel()
        runningProcess?.terminate()
    }

    /// Debounce, then search; `completion` runs on main with the rows. An
    /// empty query completes at once with nothing.
    /// `compact` stacks the snippet under the coordinates for narrow hosts.
    func search(_ query: String, compact: Bool = false, completion: @escaping ([SummonItem]) -> Void) {
        pendingSearch?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            completion([])
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.run(trimmed, compact: compact, completion: completion) }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// A row's coordinates, or nil for the tail row.
    static func location(of item: SummonItem, root: String) -> (url: URL, line: Int, column: Int)? {
        guard item.id != moreRowId else { return nil }
        let parts = item.id.split(separator: "\u{0}").map(String.init)
        guard parts.count == 3, let line = Int(parts[1]), let column = Int(parts[2]) else { return nil }
        return (URL(fileURLWithPath: "\(root)/\(parts[0])"), line, column)
    }

    private func run(_ query: String, compact: Bool, completion: @escaping ([SummonItem]) -> Void) {
        let root = self.root
        searchQueue.async { [weak self] in
            self?.runningProcess?.terminate()

            let process = Process()
            if let rg = Self.ripgrepPath {
                process.executableURL = URL(fileURLWithPath: rg)
                process.arguments = [
                    "--fixed-strings", "--smart-case", "--line-number", "--column",
                    "--no-heading", "--color", "never", "--max-columns", "240",
                    "--", query,
                ]
                process.currentDirectoryURL = URL(fileURLWithPath: root)
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["-C", root, "grep", "-In", "--column", "-F", "-e", query]
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return }
            self?.runningProcess = process
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            // Exit 1 = no matches for both tools; only a crash is a real error,
            // and its honest rendering is the empty offer.
            guard process.terminationStatus <= 1 else { return }

            let lines = String(data: data, encoding: .utf8)?
                .split(separator: "\n").prefix(Self.cap + 1) ?? []
            var items: [SummonItem] = []
            for raw in lines.prefix(Self.cap) {
                // path:line:col:text — code text may contain colons, so split
                // is bounded.
                let parts = raw.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count == 4, let line = Int(parts[1]), let column = Int(parts[2]) else { continue }
                items.append(Self.item(
                    rel: String(parts[0]), line: line, column: column, snippet: String(parts[3]), compact: compact
                ))
            }
            if lines.count > Self.cap {
                items.append(SummonItem(
                    id: Self.moreRowId,
                    text: NSAttributedString(
                        string: "… more matches — narrow the query",
                        attributes: [
                            .font: Theme.Typography.ui(Theme.Typography.small),
                            .foregroundColor: Theme.chromeMutedText,
                        ]
                    ),
                    matchText: "",
                    chord: nil
                ))
            }
            DispatchQueue.main.async { completion(items) }
        }
    }

    private static func item(rel: String, line: Int, column: Int, snippet: String, compact: Bool) -> SummonItem {
        let name = (rel as NSString).lastPathComponent
        let text = NSMutableAttributedString()
        // File coordinates and code are terminal-pasteable: mono (§1.4).
        text.append(NSAttributedString(string: "\(name):\(line)", attributes: [
            .font: Theme.Typography.mono(Theme.Typography.small, weight: .medium),
            .foregroundColor: Theme.chromeText,
        ]))
        let snippetText = NSAttributedString(
            string: "\(compact ? "" : "  ")\(snippet.trimmingCharacters(in: .whitespaces))",
            attributes: [
                .font: Theme.Typography.mono(Theme.Typography.small),
                .foregroundColor: Theme.chromeMutedText,
            ]
        )
        if !compact { text.append(snippetText) }
        return SummonItem(
            id: "\(rel)\u{0}\(line)\u{0}\(column)",
            text: text,
            matchText: rel.lowercased(),
            chord: nil,
            detail: compact ? snippetText : nil
        )
    }

    /// rg when installed (Homebrew paths + PATH), else git grep.
    private static let ripgrepPath: String? = {
        for candidate in ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        probe.arguments = ["sh", "-c", "command -v rg"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        try? probe.run()
        probe.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }()
}

final class RepoSearchOverlay: SummonCardOverlay {
    private let engine: RepoTextSearch
    private let onOpen: (URL, Int, Int) -> Void

    init(root: String, onDismiss: @escaping () -> Void, onOpen: @escaping (URL, Int, Int) -> Void) {
        self.engine = RepoTextSearch(root: root)
        self.onOpen = onOpen
        super.init(
            summonStyle: .init(
                placeholder: "Find in repo…",
                // The query is code text — mono; the placeholder is Atelier
                // speaking (§1.4).
                fieldFont: Theme.Typography.mono(Theme.Typography.body),
                placeholderFont: Theme.Typography.ui(Theme.Typography.body),
                rowHeight: 24,
                rowInset: 14,
                noMatchText: "No matches",
                escClearsQueryFirst: true,
                filtersLocally: false
            ),
            maxListHeight: 19 * 24, // taller than the pickers — results want room
            onDismiss: onDismiss
        )

        summon.onQueryChange = { [weak self] query in
            guard let self else { return }
            self.engine.search(query) { [weak self] items in self?.summon.setItems(items) }
        }
        summon.onActivate = { [weak self] item in
            guard let self, let hit = RepoTextSearch.location(of: item, root: self.engine.root) else { return }
            self.dismiss()
            self.onOpen(hit.url, hit.line, hit.column)
        }
    }
}
