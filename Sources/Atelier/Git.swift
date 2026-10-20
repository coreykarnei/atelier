import Foundation

/// Every git Atelier runs goes through here, so a repo's own config can't
/// turn one of its reads into a command (2026-10 security pass). A folder
/// that ships its own `.git/config` — an archive, a shared folder; a clone
/// never copies one — can name a `core.fsmonitor` program, which
/// `ls-files`, `status` and `grep` run, as a child of Atelier, the moment a
/// project opens there. `-c` outranks the repo's config. Clean and process
/// filters (`status` runs them) can't be switched off this way, so the
/// calls that reach them wait for a trusted folder (`FolderTrust`).
enum Git {
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    /// Config every invocation carries, ahead of its own arguments.
    static let hardening = ["-c", "core.fsmonitor=false"]

    /// A configured `git` process, not yet started.
    static func process(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = hardening + arguments
        return process
    }
}
