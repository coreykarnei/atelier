#!/usr/bin/env python3
"""Remote-side atelier-notify (phase 3 of remote sessions).

The Mac binary's job — read the Claude Code hook payload on stdin, write one
NotifyMessage line to Atelier's unix socket — is trivial enough that a stdlib
python script beats cross-compiling Swift for the host. Installed by
provision.sh to ~/.local/bin/atelier-notify on the remote; the socket path it
targets is the `ssh -R`-forwarded twin of the Mac's
~/.local/state/atelier/notify.sock, so a message written here surfaces as tab
attention (and a banner) on the Mac.

Kind/title/body mapping mirrors Sources/atelier-notify/main.swift — keep them
in lockstep. Exits 0 on any failure: a notification helper must never break
the agent's hook chain.
"""
import json
import os
import socket
import sys

KINDS = {
    # Notification hook, matcher `permission_prompt` — a genuine blocker.
    "blocked": ("blocked", "Claude needs you", "Permission or a question is blocking the agent."),
    "input-blocked": ("blocked", "Claude needs you", "Permission or a question is blocking the agent."),
    "permission": ("blocked", "Claude needs you", "Permission or a question is blocking the agent."),
    # Notification hook, matcher `idle_prompt` — a minute after every Stop;
    # the app only uses it to correct a mark that missed the turn's end.
    "waiting": ("inputNeeded", "Claude is waiting", "The agent is waiting on your next prompt."),
    "input-waiting": ("inputNeeded", "Claude is waiting", "The agent is waiting on your next prompt."),
    "idle": ("inputNeeded", "Claude is waiting", "The agent is waiting on your next prompt."),
    # Legacy unmatched Notification hook.
    "input": ("inputNeeded", "Claude needs you", "The agent is waiting for input."),
    "inputNeeded": ("inputNeeded", "Claude needs you", "The agent is waiting for input."),
    "notification": ("inputNeeded", "Claude needs you", "The agent is waiting for input."),
    # UserPromptSubmit — tab state only, no banner.
    "working": ("working", "", ""),
    # PostToolUse / PostToolUseFailure — a tool returned, the turn is moving
    # (the one signal after an approved permission prompt). Main agent only.
    "tool": ("working", "", ""),
    "prompt": ("working", "", ""),
    # SessionStart — launch, /resume, /clear: the tab follows the new
    # conversation id, and `source` says empty (grey) or resumed. Tab state only.
    "session": ("session", "", ""),
    "stop": ("stop", "Claude finished", "The agent completed its turn."),
}


def pending_work(payload):
    """What Claude is waiting on, from a Stop payload's `background_tasks`:
    its background agents and workflows, which wake it when they finish.
    Shells and monitors may never end, and Claude stops counting teammates
    and cloud sessions while they idle or run long, so those are left out.
    Mirrors NotifyMessage.pendingWork in AtelierIPC.swift."""
    work = []
    for task in payload.get("background_tasks") or []:
        if not isinstance(task, dict) or task.get("status") == "paused":
            continue
        kind = task.get("type")
        if kind == "subagent":
            kind, name = "agent", task.get("description")
        elif kind == "workflow":
            name = task.get("name") or task.get("description")
        else:
            continue
        name = ((name or "").splitlines() or [""])[0]
        if len(name) > 60:
            name = name[:59] + "\u2026"
        work.append({"kind": kind, "name": name})
        if len(work) == 16:
            break
    return work


def main():
    args = sys.argv[1:]
    verb = args[0] if args else "stop"
    kind, title, body = KINDS.get(verb, KINDS["stop"])
    override = " ".join(args[1:])
    if override:
        body = override

    # Best-effort session id from the hook's stdin payload. Only read when
    # stdin is a pipe (hooks always pipe; a stray manual TTY run skips).
    session_id = None
    source = None
    pending = []
    if not sys.stdin.isatty():
        try:
            payload = json.load(sys.stdin)
            session_id = payload.get("session_id")
            source = payload.get("source")
            # A Stop with background agents or workflows still running isn't
            # the end of the work: Claude wakes itself when they finish.
            if kind == "stop":
                pending = pending_work(payload)
            # A subagent's tools report under the parent's session id, even
            # after the parent's Stop — only the main agent's tools speak.
            if verb == "tool" and payload.get("agent_id") is not None:
                return
        except Exception:
            pass

    message = {"kind": kind, "title": title, "body": body}
    if session_id:
        message["sessionId"] = session_id
    # The Atelier tab this agent was spawned for (survives /resume, /clear).
    tab = os.environ.get("ATELIER_TAB")
    if tab:
        message["tab"] = tab
    if kind == "session" and source:
        message["source"] = source
    if pending:
        message["pending"] = pending

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2)
    sock.connect(os.path.expanduser("~/.local/state/atelier/notify.sock"))
    sock.sendall((json.dumps(message) + "\n").encode())
    sock.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
