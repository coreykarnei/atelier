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
        // `theme` should find Theme.swift before a path that merely scatters
        // t-h-e-m-e: substring-in-name > fuzzy-in-name > path-only match.
        summon.rank = { item, query in
            let name = (item.id as NSString).lastPathComponent.lowercased()
            if name.contains(query) { return 3 }
            if fuzzyMatches(query: query, candidate: name) { return 2 }
            return 1
        }
        offerRecents()
        gatherFiles()
    }

    /// Recents render instantly so the card never opens empty-handed.
    private func offerRecents() {
        summon.setItems(Self.items(
            relativePaths: RecentFilesStore.recents(for: root).compactMap { path in
                path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : nil
            },
            root: root, recents: []
        ))
    }

    /// The full offer: `git ls-files --cached --others --exclude-standard`,
    /// gathered off-main (a big repo shouldn't stall the descent), recents
    /// leading. The live query survives the swap (SummonList preserves it).
    private func gatherFiles() {
        let root = self.root
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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

            let recents = RecentFilesStore.recents(for: root).compactMap { path in
                path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : nil
            }
            let recentSet = Set(recents)
            let ordered = recents + files.filter { !recentSet.contains($0) }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.summon.setItems(Self.items(relativePaths: ordered, root: root, recents: recentSet))
            }
        }
    }

    private static func items(relativePaths: [String], root: String, recents: Set<String>) -> [SummonItem] {
        relativePaths.map { rel in
            let name = (rel as NSString).lastPathComponent
            let dir = (rel as NSString).deletingLastPathComponent

            let text = NSMutableAttributedString()
            // Filenames and paths are terminal-pasteable: mono (§1.4). Same
            // row anatomy as the landing — name leads, home muted behind it.
            text.append(NSAttributedString(string: name, attributes: [
                .font: Theme.Typography.mono(Theme.Typography.body, weight: .medium),
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
