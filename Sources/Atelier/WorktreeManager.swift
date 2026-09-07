import Foundation

/// One git worktree of a repo. `isPrimary` marks the main checkout.
struct Worktree {
    let path: String
    let branch: String
    let isPrimary: Bool
}

/// Git plumbing for first-class worktrees (MILESTONE_1 §6) — a direct port of the
/// `ide -b` / `ide -rm` semantics: worktrees live at
/// `~/.local/share/worktrees/<repo>/<safe-branch>/`, always anchored to the primary
/// working tree (resolved via `--git-common-dir`, so creating from inside a worktree
/// can never nest).
enum WorktreeManager {
    static var base: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/share/worktrees"
    }

    enum Failure: LocalizedError {
        case notARepo(String)
        case git(String)

        var errorDescription: String? {
            switch self {
            case .notARepo(let cwd): return "Not a git repository: \(cwd)"
            case .git(let message): return message
            }
        }
    }

    /// The primary working tree containing `cwd` — correct even when `cwd` is
    /// inside a linked worktree.
    static func repoRoot(for cwd: String) -> String? {
        let result = git(["-C", cwd, "rev-parse", "--git-common-dir"])
        guard result.status == 0 else { return nil }
        var common = result.out
        if !common.hasPrefix("/") { common = "\(cwd)/\(common)" }
        return ((common as NSString).deletingLastPathComponent as NSString).standardizingPath
    }

    /// All worktrees of the repo, primary first (git guarantees that ordering).
    /// Prunable entries — a checkout whose directory is gone (a scratch
    /// worktree left by some tool) — are dropped; a detached checkout is named
    /// by its directory rather than "(detached)".
    static func list(repoRoot: String) -> [Worktree] {
        let result = git(["-C", repoRoot, "worktree", "list", "--porcelain"])
        guard result.status == 0 else { return [] }

        var out: [Worktree] = []
        var path: String?
        var branch: String?
        var isFirst = true
        func flush() {
            defer { path = nil; branch = nil }
            guard let p = path else { return }
            let primary = isFirst
            isFirst = false
            guard FileManager.default.fileExists(atPath: p) else { return }
            out.append(Worktree(
                path: p,
                branch: branch ?? "\((p as NSString).lastPathComponent) (detached)",
                isPrimary: primary
            ))
        }
        for line in result.out.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            } else if line == "detached" {
                branch = "(detached)"
            }
        }
        flush()
        return out
    }

    /// The branch checked out at `path` (nil when detached or not a repo).
    static func currentBranch(_ path: String) -> String? {
        let result = git(["-C", path, "symbolic-ref", "--short", "-q", "HEAD"])
        return result.status == 0 && !result.out.isEmpty ? result.out : nil
    }

    /// Uncommitted changes (staged, unstaged, or untracked)?
    static func isDirty(_ path: String) -> Bool {
        let result = git(["-C", path, "status", "--porcelain"])
        return result.status == 0 && !result.out.isEmpty
    }

    /// The actual `git status --short` lines — what a refusal names as the loss
    /// (POLISH_PLAN §5: refusals as designed objects).
    static func statusLines(_ path: String) -> [String] {
        let result = git(["-C", path, "status", "--short"])
        guard result.status == 0 else { return [] }
        return result.out.split(separator: "\n").map(String.init)
    }

    /// `feature/foo` → `feature-foo`, for the on-disk directory name.
    static func safeBranch(_ branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "-")
    }

    /// Create (or reuse) the worktree for `branch` and return its path. Existing
    /// local/remote branches are checked out; a new name branches from `main`.
    static func create(branch: String, repoRoot: String) throws -> String {
        let repoName = (repoRoot as NSString).lastPathComponent
        let path = "\(base)/\(repoName)/\(safeBranch(branch))"

        if FileManager.default.fileExists(atPath: path) { return path }
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        let exists =
            git(["-C", repoRoot, "show-ref", "--verify", "--quiet", "refs/heads/\(branch)"]).status == 0 ||
            git(["-C", repoRoot, "show-ref", "--verify", "--quiet", "refs/remotes/origin/\(branch)"]).status == 0

        let result = exists
            ? git(["-C", repoRoot, "worktree", "add", path, branch])
            : git(["-C", repoRoot, "worktree", "add", "-b", branch, path, "main"])
        guard result.status == 0 else {
            throw Failure.git(result.err.isEmpty ? "git worktree add failed" : result.err)
        }
        return path
    }

    /// Remove a worktree. Without `force`, git refuses a dirty tree — we surface
    /// that refusal rather than defaulting to `--force` (no quiet data loss).
    static func remove(path: String, repoRoot: String, force: Bool) throws {
        var args = ["-C", repoRoot, "worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        let result = git(args)
        guard result.status == 0 else {
            throw Failure.git(result.err.isEmpty ? "git worktree remove failed" : result.err)
        }
    }

    // MARK: Process

    private static func git(_ args: [String]) -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch { return (1, "", "\(error)") }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, out, err)
    }
}
