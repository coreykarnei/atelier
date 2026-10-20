import AppKit

/// Whether Atelier runs a folder's own code on its own initiative (2026-10
/// security pass; owner call 2026-10-20). Three things Atelier starts by
/// itself execute what a folder brings: `git status` runs the repo's clean
/// and process filters, a language server runs its build scripts and proc
/// macros, the Python server runs its venv's interpreter. In a folder that
/// isn't trusted those wait — and so does creating or removing a worktree,
/// which runs hooks and filters — while the editor, the tree, search and the
/// terminals carry on.
///
/// The answer is Claude's own. Claude Code asks "Do you trust the files in
/// this folder?" the first time it runs somewhere and records the yes in
/// `~/.claude.json`, so one question serves both. Only the folder's own
/// record counts — the folder, its repo, or a worktree's main checkout —
/// never an ancestor's: a trusted home folder (or `/`, which the owner's
/// record holds) must not vouch for everything beneath it. Where Claude has
/// no yes on record, or its file can't be read, the explorer's Restricted
/// mark gives Atelier's own, kept in its defaults.
enum FolderTrust {
    /// Posted on the main thread when an answer arrives — Claude's, read from
    /// its file, or Atelier's own.
    static let didChange = Notification.Name("FolderTrust.didChange")

    static func isTrusted(_ folder: String) -> Bool {
        startWatching()
        let keys = candidates(for: folder)
        let own = ownTrusted
        if keys.contains(where: own.contains) { return true }
        let claude = ClaudeRecord.shared.trusted
        return keys.contains(where: claude.contains)
    }

    /// Atelier's own yes, for a folder Claude hasn't vouched for.
    static func trust(_ folder: String) {
        var own = ownTrusted
        own.insert(folder)
        UserDefaults.standard.set(own.sorted(), forKey: ownKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static let ownKey = "trust.folders"

    private static var ownTrusted: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ownKey) ?? [])
    }

    /// The paths whose record speaks for `folder`: itself and the repo's
    /// primary checkout (which also covers a worktree and a sub-folder),
    /// each as written and with symlinks resolved — Claude records the
    /// resolved form.
    private static func candidates(for folder: String) -> [String] {
        if let known = candidateCache[folder] { return known }
        var paths = [folder]
        if let repo = WorktreeManager.repoRoot(for: folder) { paths.append(repo) }
        paths += paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        var seen = Set<String>()
        let unique = paths.filter { seen.insert($0).inserted }
        candidateCache[folder] = unique
        return unique
    }

    private static var candidateCache: [String: [String]] = [:]

    /// Claude writes its file whenever it records a yes; a cheap stat every
    /// two seconds notices, and a changed answer is announced.
    private static var watch: Timer?

    private static func startWatching() {
        guard watch == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            if ClaudeRecord.shared.reloadIfChanged() {
                NotificationCenter.default.post(name: didChange, object: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
    }
}

/// The folders Claude Code has a trust yes for, read from its config file
/// (`$CLAUDE_CONFIG_DIR/.claude.json`, else `~/.claude.json`): each
/// `projects` key whose `hasTrustDialogAccepted` is true. Re-read only when
/// the file's modification time or size changes.
private final class ClaudeRecord {
    static let shared = ClaudeRecord()

    private(set) var trusted: Set<String> = []
    private var stamp: (Date, Int)?

    private init() { _ = reloadIfChanged() }

    private var path: String {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return (dir as NSString).appendingPathComponent(".claude.json")
        }
        return NSHomeDirectory() + "/.claude.json"
    }

    /// Whether the trusted set changed.
    func reloadIfChanged() -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let now = (attributes?[.modificationDate] as? Date ?? .distantPast,
                   (attributes?[.size] as? NSNumber)?.intValue ?? -1)
        if let stamp, stamp == now { return false }
        stamp = now
        var fresh: Set<String> = []
        if let data = FileManager.default.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let projects = json["projects"] as? [String: Any] {
            for (folder, value) in projects {
                if let record = value as? [String: Any], record["hasTrustDialogAccepted"] as? Bool == true {
                    fresh.insert(folder)
                }
            }
        }
        guard fresh != trusted else { return false }
        trusted = fresh
        return true
    }
}
