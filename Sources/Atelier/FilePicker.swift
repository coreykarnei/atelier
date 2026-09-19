import AppKit

/// Recently opened files, most-recent-first, per repo root. They lead the
/// picker's offer the way landing recents lead the landing.
enum RecentFilesStore {
    private static let key = "editor.recentFiles"
    private static let cap = 20

    private static func all() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }

    static func recents(for root: String) -> [String] {
        (all()[root] ?? []).filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func record(_ path: String, root: String) {
        var store = all()
        var list = (store[root] ?? []).filter { $0 != path }
        list.insert(path, at: 0)
        store[root] = Array(list.prefix(cap))
        UserDefaults.standard.set(store, forKey: key)
    }
}

/// `⌘P` — the fuzzy file picker (M2.2, TECHNICAL_PLAN §3.4). The summon card
/// over the repo's files: `git ls-files` (tracked + untracked, .gitignore
/// respected) gathered off-main and offered the moment they land, recently
/// opened files first. Typing fuzzy-matches the whole relative path, so `tvc`
/// finds `Sources/.../TextViewController.swift`.
/// The repo's file offer, shared by ⌘P and the explorer's search bar:
/// `git ls-files` (tracked + untracked, .gitignore honoured), recents
/// leading, one row anatomy, one ranking.
enum RepoFileOffer {
    /// The offer stops here, with an honest tail row: every row is an
    /// attributed string held on main, and a root the size of a home
    /// directory listed unbounded once (2026-09-18) — the tree reloaded off
    /// every FSEvents batch under `~`, each reload spawned another
    /// `git ls-files` + `git status --ignored` over all of it, sixty-odd git
    /// processes piled up, and the main thread spent its time freeing the
    /// last multi-hundred-thousand-row offer while the next one landed —
    /// every keystroke starved while the pointer still moved.
    static let cap = 20_000
    static let moreRowId = "__more-files__"

    /// A root no repo scan should walk in full: the home directory (or `/`).
    /// `git status --ignored` there descends into `~/Library/Containers`, and
    /// macOS answers each walk with an "access data from other apps" prompt
    /// billed to Atelier — a dozen of them queued behind the stalled main
    /// thread on 2026-09-18. Sessions rooted there get recents only and no
    /// ignore dimming; anything under `~/repositories` is unaffected.
    static func isUnboundedRoot(_ root: String) -> Bool {
        var resolved = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        while resolved.count > 1, resolved.hasSuffix("/") { resolved.removeLast() }
        var home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        return resolved == "/" || resolved == home
    }

    /// Gather off-main; `completion` always runs on main — with the finished
    /// items, or with recents alone when git can't run or the root is
    /// unbounded. Callers single-flight on that promise.
    static func gather(root: String, rowFont: CGFloat = Theme.Typography.body, completion: @escaping ([SummonItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let recents = recentRelativePaths(root: root)
            guard !isUnboundedRoot(root) else {
                let built = items(relativePaths: recents, root: root, rowFont: rowFont)
                DispatchQueue.main.async { completion(built) }
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            // `-- .` bounds the listing to the session folder: a root that is
            // a sub-folder of its repo lists its own subtree, not the repo.
            process.arguments = ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "--", "."]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            var files: [String] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                files = String(data: data, encoding: .utf8)?
                    .split(separator: "\n").map(String.init) ?? []
            }

            let recentSet = Set(recents)
            let ordered = recents + files.filter { !recentSet.contains($0) }
            var built = items(relativePaths: Array(ordered.prefix(cap)), root: root, rowFont: rowFont)
            if ordered.count > cap {
                built.append(SummonItem(
                    id: moreRowId,
                    text: NSAttributedString(
                        string: "… more files — narrow the query",
                        attributes: [
                            .font: Theme.Typography.ui(Theme.Typography.small),
                            .foregroundColor: Theme.chromeMutedText,
                        ]
                    ),
                    matchText: "",
                    chord: nil
                ))
            }
            DispatchQueue.main.async { completion(built) }
        }
    }

    static func recentRelativePaths(root: String) -> [String] {
        RecentFilesStore.recents(for: root).compactMap { path in
            path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : nil
        }
    }

    /// `theme` should find Theme.swift before a path that merely scatters
    /// t-h-e-m-e: substring-in-name > fuzzy-in-name > path-only match.
    static func rank(_ item: SummonItem, _ query: String) -> Int {
        let name = (item.id as NSString).lastPathComponent.lowercased()
        if name.contains(query) { return 3 }
        if fuzzyMatches(query: query, candidate: name) { return 2 }
        return 1
    }

    static func items(relativePaths: [String], root: String, rowFont: CGFloat = Theme.Typography.body) -> [SummonItem] {
        relativePaths.map { rel in
            let name = (rel as NSString).lastPathComponent
            let dir = (rel as NSString).deletingLastPathComponent

            let text = NSMutableAttributedString()
            // Filenames and paths are terminal-pasteable: mono (§1.4). Same
            // row anatomy as the landing — name leads, home muted behind it.
            text.append(NSAttributedString(string: name, attributes: [
                .font: Theme.Typography.mono(rowFont, weight: .medium),
                .foregroundColor: Theme.chromeText,
            ]))
            if !dir.isEmpty {
                text.append(NSAttributedString(string: "  \(dir)", attributes: [
                    .font: Theme.Typography.mono(Theme.Typography.small),
                    .foregroundColor: Theme.chromeMutedText,
                ]))
            }
            return SummonItem(
                id: "\(root)/\(rel)",
                text: text,
                matchText: rel.lowercased(),
                chord: nil
            )
        }
    }
}

final class FilePicker: SummonCardOverlay {
    private let root: String
    private let onOpen: (URL) -> Void

    init(root: String, onDismiss: @escaping () -> Void, onOpen: @escaping (URL) -> Void) {
        self.root = root
        self.onOpen = onOpen
        super.init(
            summonStyle: .init(
                placeholder: "Go to file…",
                // The query is a path fragment — terminal-pasteable, so mono
                // (§1.4); the placeholder is Atelier speaking.
                fieldFont: Theme.Typography.mono(Theme.Typography.body),
                placeholderFont: Theme.Typography.ui(Theme.Typography.body),
                rowHeight: 24,
                rowInset: 14,
                noMatchText: "No matching files",
                escClearsQueryFirst: false
            ),
            onDismiss: onDismiss
        )

        summon.onActivate = { [weak self] item in
            guard let self, item.id != RepoFileOffer.moreRowId else { return }
            RecentFilesStore.record(item.id, root: self.root)
            self.dismiss()
            self.onOpen(URL(fileURLWithPath: item.id))
        }
        summon.rank = RepoFileOffer.rank
        offerRecents()
        RepoFileOffer.gather(root: root) { [weak self] items in self?.summon.setItems(items) }
    }

    /// Recents render instantly so the card never opens empty-handed.
    private func offerRecents() {
        summon.setItems(RepoFileOffer.items(relativePaths: RepoFileOffer.recentRelativePaths(root: root), root: root))
    }

}
