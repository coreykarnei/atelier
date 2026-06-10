import Foundation
import AtelierIPC

// atelier — the workspace CLI (MILESTONE_1 §6), successor to the `ide` script.
//
//   atelier [path]            open/focus the Atelier project for path (default .)
//   atelier -b <branch> [path]   open a worktree session for <branch>
//   atelier -rm <branch> [path]  remove the worktree for <branch>
//
// Sends one CommandMessage to the running app's socket; if the app isn't running,
// launches it and retries. Repo resolution happens in the app (same plumbing the
// worktree fan uses).

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("atelier: \(message)\n".utf8))
    exit(1)
}

var branch: String?
var removeBranch: String?
var targetArg: String?

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-b":
        guard !args.isEmpty else { fail("-b requires a branch name") }
        branch = args.removeFirst()
    case "-rm":
        guard !args.isEmpty else { fail("-rm requires a branch name") }
        removeBranch = args.removeFirst()
    case "-h", "--help":
        print("usage: atelier [path] | atelier -b <branch> [path] | atelier -rm <branch> [path]")
        exit(0)
    default:
        targetArg = arg
    }
}

let cwd = FileManager.default.currentDirectoryPath
let target = URL(fileURLWithPath: targetArg ?? ".", relativeTo: URL(fileURLWithPath: cwd))
    .standardizedFileURL.path
guard FileManager.default.fileExists(atPath: target) else {
    fail("no such directory: \(target)")
}

let message: CommandMessage
if let removeBranch {
    message = CommandMessage(verb: .worktreeRemove, path: target, branch: removeBranch)
} else if let branch {
    message = CommandMessage(verb: .worktreeAdd, path: target, branch: branch)
} else {
    message = CommandMessage(verb: .open, path: target)
}

let line = message.encodedLine()
if AtelierIPC.send(line: line) { exit(0) }

// App not running — launch it and retry until the socket appears.
let launcher = Process()
launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
launcher.arguments = ["-b", "dev.sterlingcore.atelier"]
try? launcher.run()
launcher.waitUntilExit()
guard launcher.terminationStatus == 0 else {
    fail("Atelier isn't running and couldn't be launched")
}

for _ in 0..<40 { // ~10s
    usleep(250_000)
    if AtelierIPC.send(line: line) { exit(0) }
}
fail("launched Atelier, but its socket never came up")
