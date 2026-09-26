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
    # Notification hook, matcher `idle_prompt` — done, your move.
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
    # conversation id. Tab state only.
    "session": ("session", "", ""),
    "stop": ("stop", "Claude finished", "The agent completed its turn."),
}


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
    if not sys.stdin.isatty():
        try:
            payload = json.load(sys.stdin)
            session_id = payload.get("session_id")
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
