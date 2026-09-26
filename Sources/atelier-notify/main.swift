import Foundation
import AtelierIPC

// atelier-notify <stop|input|working|tool|session> [message...]
//
// Invoked by Claude Code's Stop / Notification / UserPromptSubmit /
// PostToolUse(Failure) / SessionStart hooks — the ones Atelier passes
// every agent it spawns (`AgentHooks`). Connects
// to the running Atelier app's unix socket and sends one NotifyMessage. If Atelier
// isn't running (no socket / refused), it exits 0 silently — a notification helper
// must never break the agent's hook chain.
//
// Claude Code passes the hook payload as JSON on stdin; we read it for the
// session_id so the app can badge / focus the exact session tab.

let args = Array(CommandLine.arguments.dropFirst())
let kindArg = args.first ?? "stop"

let kind: NotifyMessage.Kind
let defaultTitle: String
let defaultBody: String
switch kindArg {
case "blocked", "input-blocked", "permission":
    // Notification hook, matcher `permission_prompt` — a genuine blocker.
    kind = .blocked
    defaultTitle = "Claude needs you"
    defaultBody = "Permission or a question is blocking the agent."
case "waiting", "input-waiting", "idle":
    // Notification hook, matcher `idle_prompt` — done, your move.
    kind = .inputNeeded
    defaultTitle = "Claude is waiting"
    defaultBody = "The agent is waiting on your next prompt."
case "input", "inputNeeded", "notification":
    // Unmatched Notification hook (a settings.json without the matchers):
    // treated as "your move"; only the `permission_prompt` matcher can raise
    // a blocker.
    kind = .inputNeeded
    defaultTitle = "Claude needs you"
    defaultBody = "The agent is waiting for input."
case "working", "prompt", "tool":
    // UserPromptSubmit, and PostToolUse/PostToolUseFailure (`tool`): a tool
    // just returned, so the turn is moving — the one hook after a permission
    // prompt is approved (Claude Code fires none on the approval itself).
    kind = .working
    defaultTitle = ""
    defaultBody = ""
case "session":
    // SessionStart: launch, `/resume`, `/clear`, compaction. The payload's
    // session_id is the conversation the agent is in now; the tab follows
    // it before a word is typed.
    kind = .session
    defaultTitle = ""
    defaultBody = ""
default:
    kind = .stop
    defaultTitle = "Claude finished"
    defaultBody = "The agent completed its turn."
}

// Best-effort session id from the hook's stdin payload. Never block: only read
// when stdin is a pipe (hooks always pipe; a stray manual run from a TTY skips).
var sessionId: String?
if isatty(0) == 0 {
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    if let payload = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] {
        sessionId = payload["session_id"] as? String
        // A subagent's tool calls carry `agent_id` under the parent's
        // session id — and a background one keeps calling after the
        // parent's Stop, which would repaint a finished session blue with
        // nothing to correct it. Only the main agent's tools speak.
        if kindArg == "tool", payload["agent_id"] != nil { exit(0) }
    }
}

let override = args.dropFirst().joined(separator: " ")
let body = override.isEmpty ? defaultBody : override
let tab = ProcessInfo.processInfo.environment[NotifyMessage.tabEnvironmentKey]
let message = NotifyMessage(kind: kind, title: defaultTitle, body: body, sessionId: sessionId, tab: tab)

// Connect to the unix domain socket.
let path = AtelierIPC.socketPath()
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(path.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { exit(0) }
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { dst in
        for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
        dst[pathBytes.count] = 0
    }
}

let connected = withUnsafePointer(to: &addr) { p in
    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
        connect(fd, sp, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else { exit(0) }

let payload = message.encodedLine()
_ = payload.withUnsafeBytes { raw in
    write(fd, raw.baseAddress, raw.count)
}
exit(0)
