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
    /// Gather off-main; `completion` runs on main with the finished items.
    static func gather(root: String, rowFont: CGFloat = Theme.Typography.body, completion: @escaping ([SummonItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let files = String(data: data, encoding: .utf8)?
                .split(separator: "\n").map(String.init) ?? []

            let recents = recentRelativePaths(root: root)
            let recentSet = Set(recents)
            let ordered = recents + files.filter { !recentSet.contains($0) }
            let built = items(relativePaths: ordered, root: root, rowFont: rowFont)
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
            guard let self else { return }
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
