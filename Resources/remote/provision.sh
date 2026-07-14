#!/bin/sh
# Remote-host provisioning for Atelier remote sessions (phase 3). Run *on the
# remote* by RemoteLink over ssh, with the atelier-notify python source piped
# in on stdin. Idempotent and versioned: the marker file short-circuits every
# run after the first — bump the -v suffix here AND in Remote.swift when the
# payloads change, so existing hosts re-provision.
#
# What it sets up:
#   ~/.local/bin/atelier-notify         — the hook → forwarded-socket sender
#   ~/.claude/settings.json             — Atelier's four hook entries, merged
#                                         additively (one-time .atelier-bak)
set -e

MARKER="$HOME/.local/state/atelier/provisioned-v1"
[ -f "$MARKER" ] && exit 0

mkdir -p "$HOME/.local/bin" "$HOME/.local/state/atelier"

# The notify sender arrives on stdin.
cat > "$HOME/.local/bin/atelier-notify"
chmod +x "$HOME/.local/bin/atelier-notify"

# Merge the hook entries into ~/.claude/settings.json — additive only, no
# rewriting of anything already there, backed up once before first touch.
python3 - <<'ATELIER_MERGE_EOF'
import json, os, shutil

path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(path) as f:
        settings = json.load(f)
except (FileNotFoundError, ValueError):
    settings = {}

hooks = settings.setdefault("hooks", {})
notify = os.path.expanduser("~/.local/bin/atelier-notify")

def ensure(event, matcher, verb):
    entries = hooks.setdefault(event, [])
    command = f"{notify} {verb}"
    for entry in entries:
        for hook in entry.get("hooks", []):
            if hook.get("command") == command:
                return
    entry = {"hooks": [{"type": "command", "command": command}]}
    if matcher:
        entry["matcher"] = matcher
    entries.append(entry)

ensure("Stop", None, "stop")
ensure("Notification", "permission_prompt", "blocked")
ensure("Notification", "idle_prompt", "waiting")
ensure("UserPromptSubmit", None, "working")

if os.path.exists(path) and not os.path.exists(path + ".atelier-bak"):
    shutil.copy2(path, path + ".atelier-bak")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
ATELIER_MERGE_EOF

touch "$MARKER"
