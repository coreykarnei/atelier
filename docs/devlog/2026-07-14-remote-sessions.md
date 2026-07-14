# 2026-07-14 — Remote sessions: ide-pi, made first-class

## The ask

The owner runs Claude Code + a shell on a Raspberry Pi (`jarvis`) via the
dotfiles' `ide-pi` — nine lines of `ssh -t jarvis ide`. It works until the
SSH link dies (sleep, Wi-Fi, NAT timeout), and then recovery is manual: a
new window, a new connection, find the tmux session again. The ask was a
remote session in Atelier that *just works*: pick the host, get terminal +
claude on the Pi, never babysit the connection. Phone control was explicitly
out of scope — Claude Code's own `/remote-control` does that better than
anything Atelier could build, and it already works in a hosted pane.

## The shape

A `Session` can now be `.remote(host:)` (`Remote.swift`): both panes spawn
`ssh -t <host> -- tmux -f <conf> -L atelier new-session -A -s atelier-<id8>-{sh|ai}`
instead of local processes. The durability story has two independent halves:

1. **The work survives** because it lives in host-side tmux — a dedicated
   `-L atelier` server with a self-provisioned minimal conf (status off,
   xterm-256color, focus-events on; versioned filename, rewritten when the
   name bumps). The pane's spawn command *is* the provisioning — a wiped
   host heals on the next spawn, no ordering dependency.
2. **The view survives** because Atelier owns the pane process: ssh exit
   255 (link death — SwiftTerm reports raw waitpid status, so both
   encodings are accepted) shows the placard ("reconnecting to jarvis…",
   the resuming placard generalized with a subtitle) and respawns the same
   argv on a 1/2/5s backoff, forever. `new -A` makes every respawn a
   reattach. Exit 0 (typed `exit`, tmux kill) is a deliberate end — the
   pane goes idle like a local shell's, no zombie reattach.

Close semantics follow intent: ⌘W kills the host-side pair (after the usual
reopen grace); quit does **not** — the snapshot promised the session back,
so relaunch reattaches to a claude that never stopped running. That beats
`--resume`: the restored pane is the *same process*, mid-scrollback. When
the tmux session is gone anyway, the `new -A` command line carries
`claude --resume <id>` and the host-side transcript picks up.

Entry is the Landing: hosts parsed from `~/.ssh/config` (one `Include`
level, wildcards dropped) join the offer after repos, marked `ssh`; typing
`host:dir` injects a synthetic top row (the colon defeats subsequence
matching, so the row is made, not matched — and `refresh()` routes through
the injector so a became-key rescan can't eat a live query). A Landing
can't promote in place across machines (its shell PTY is local), so the
controller replaces it with a fresh remote session in the same tab slot.
Remote recents ride `RecentsStore` as `ssh://host:dir` ids.

Remote sessions pin Split (the editor edits local files — exactly the wrong
thing next to a remote shell), don't anchor the window (worktree fan and
⌥⌘T stay local; ⌥⌘T on a remote tab opens a sibling on the same host+dir),
skip local transcript reads (seed/custom title only), and wear `@host` on
the tab the way ⎇ marks a worktree — dropped when the title *is* the host.
Tabs group by host, like worktrees group by root.

## Attention across the wire

The tab dots work because the notify socket crosses the link, not because
anything was rebuilt: `RemoteLink` (one per host, `LSPRegistry`-shaped)
provisions the host once — a **stdlib-python** `atelier-notify` into
`~/.local/bin` (its whole job is one JSON line into a unix socket; python
beats cross-compiling Swift for ARM) plus the four hook entries merged
additively into the remote `~/.claude/settings.json` (one-time
`.atelier-bak`) — then holds `ssh -N -R <remote-sock>:<local-sock>`.
Hook fires on the Pi → python sender → forwarded socket →
`NotificationServer` → the exact tab, joined on the app-chosen
`claudeSessionId`, which is globally unique and therefore safe cross-machine.

Two forward rules, both learned the hard way against OpenSSH 9.8:

- **No mux.** A remote unix-socket forward requested through the
  ControlMaster reports success and never binds. The forward owns a direct
  connection — which also means ControlPersist expiry can't take the
  attention channel down with it.
- **Single-flight.** Forward attempts are serialized by a generation token
  checked in every async continuation, and each new attempt kills the
  previous straggler. A leaked `-N` keeps the sshd-side listener
  registration alive and every later bind fails silently — the wedge that
  motivated the token. Each (re)start `rm -f`s the stale remote socket
  first (the only alternative is server-side `StreamLocalBindUnlink`, which
  needs sshd config on every host).

Everything else — ControlMaster across the pane sshs, `ServerAliveInterval`
so death is detected in seconds, `ConnectTimeout=5` — lives in one option
set in `RemoteCommand`.

## Verified against jarvis

Spawn into `~/jarvis` via the typed `jarvis:jarvis` row; killed every
Pi-side sshd connection → both panes reattached in ~10s with claude
untouched; quit/relaunch → same tmux pair, same conversation mid-scroll;
provisioning idempotent (marker short-circuit, no duplicate hooks, backup
present); blue working dot mid-turn and peach waiting dot on stop, fed by
Pi-side hooks; `pkill`ed the forward → self-healed in one retry and the
next prompt's dot still arrived; quit reaps the forward; restore with the
host unplugged lands in the reconnecting placard instead of an orphan alert.

## Follow-ups (not blocking)

- Live tab titles for remote sessions (read the transcript's `ai-title`
  over the ControlMaster link on the 2s tick).
- tmux inside the pane costs some copy/scrollback fidelity vs. Atelier's
  local truthful-copy guarantees — accepted for remote panes; revisit only
  if it grates.
- The hooks provisioned on the host fire for *any* claude session there
  (same as the Mac-side hooks locally); events for unknown session ids
  don't match a tab, but they do banner. Same behavior as local — noted.
