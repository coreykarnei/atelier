# The security pass — 2026-10-20

Atelier had never had a security review of its own. It got one from
outside: a corporate review rejected it, partly on process (AI tools go
through a separate approval) and partly on a scanner's report. The
scanner's severities were inflated and its framing was one-note — every
finding hung off "the socket is unauthenticated" — but its root finding
was right, and it was embarrassing: the whole developer probe surface
shipped in the notarized release.

## How the review was done

Three reviewers with different temperaments audited the tree
independently across six layers (IPC, process spawning, untrusted content,
files and saved state, platform privileges, build and release), then
cross-examined each other's findings and voted. One leaned red team and
only filed what it could walk end to end, one thought in macOS primitives
and asked what stops each attack when the layer above fails, and one
calibrated: is the path reachable in the build that ships, and does the
app give an attacker anything they didn't already have? That last
question set the threat model. Something that needs code already running
as the user is capped low — that code could edit `~/.zshrc` — unless
Atelier hands it something more. Usually what it hands over is Atelier's
macOS privacy grants: Atelier is the "responsible process" for every
shell and agent it hosts, so their commands run with whatever Documents,
Desktop or Full Disk Access the app holds.

Fifteen findings survived. Several weren't in the scanner's report and
mattered more than most that were.

## What was wrong, and what changed

**The probes shipped.** `DebugMessage` — `probe:shell=` types a command
into the shell, `probe:type=` drives Claude and can answer its permission
prompts, `probe:menu=` performs any selector, `snapshot` and `lspProbe`
write wherever they're told — was compiled into every build and answered
anything that could write to the socket. It now exists only under
`ATELIER_PROBES`, a define Package.swift sets for debug builds, and even
there it answers only an instance launched with `ATELIER_STATE_DIR` — a
test or film build. `release.sh` refuses a binary that carries the
strings.

**Remote sessions are gone.** They were the other half of the external
report: a saved host name reached ssh's argv ahead of `--`, a conversation
id reached a remote `bash -lc` unquoted, and the `ssh -R` socket forward
handed every host with a live session the Mac's whole socket, probes
included. The owner didn't use them, so they went entirely (tag
`pre-remote-strip`). Old saved state still decodes: `PersistedWindow
.loadable()` leaves a remote session behind on load and finds the active
tab again by conversation, because deleting the field would have made such
a session decode as a local one.

**Opening a folder ran its code.** The file explorer runs `git status` the
moment a project opens, and git honours what a repository's own config
asks for: a `core.fsmonitor` program, clean and process filters. A clone
never copies `.git/config`, but an archive or a shared folder can carry
one. Language servers run build scripts and proc macros by design. The
Python server was pointed at the repo's `.venv/bin/python`, with
`.venv/bin` first on PATH — and pyright-langserver is a
`#!/usr/bin/env node` script, so a committed `.venv/bin/node` ran before
the server did. Three changes:

- Every git Atelier runs goes through `Git.process`, which passes
  `-c core.fsmonitor=false`.
- No repo directory goes on a language server's PATH. Relative PATH
  entries are dropped from the server search path.
- `FolderTrust` holds back what can't be made safe: git status, language
  servers and venv adoption, and worktree creation and removal. The answer
  is Claude Code's own: the yes it records in `~/.claude.json` when it
  asks whether to trust a folder. One question serves both, and answering
  it lights the tree and the server up within two seconds. Only the
  folder's own record counts — the folder, its repo, or a worktree's main
  checkout — never an ancestor's. The owner's record trusts `~` and `/`,
  and a parent rule would have trusted `~/Downloads`. Where there's no yes
  on record, the explorer header's lock offers Atelier's own.

**Every terminal could reach every other.** `forkpty` then `execve` closed
nothing, so each shell and agent held the listening socket and the
primary side of every other session's terminal; `lsof` on the live app
showed about 25. A process in one pane — a build script, a
prompt-injected command, Claude Code's sandbox included — could type into
another agent. SwiftTerm patch 12 closes every descriptor above 2 in the
child. Atelier marks its own close-on-exec too.

**The promote `cd` was injectable.** Promoting a Landing typed
`cd '<root>'` into zsh, so a `'` in a folder name ended the quoting and
the rest ran. The path is now one quoted shell word, and a name with
control characters isn't typed at all.

**Terminal content.**
- Pastes lose their control characters (patch 13), so `ESC [201~` on the
  clipboard can't end bracketed paste early.
- A program setting the clipboard (OSC 52) now shows a two-second notice
  in its pane. Claude's copy relies on it, so it stays on (owner call).
- ⌘-clicking something that runs (an app, a script, an installer, an
  executable, a file that opens in a terminal, a link for another app)
  asks first through `LinkPolicy`. The question names the full target,
  since OSC 8 text can say anything. The Markdown preview's links go the
  same way.

**Smaller things.**
- The state directory is 0700, refused if it's a symlink or someone
  else's. The socket is 0600; `session.json` and `shelf.json` are 0600 and
  written atomically.
- A client that connects and never writes times out after 500ms instead
  of stalling every hook and quit.
- A notify message no hosted session claims posts no banner.
- Conversation ids must be UUIDs, both from hooks and from disk.
- Release builds are reproducible and checked:
  - The vendored editor packages no longer run the SwiftLint build plugin,
    which downloaded and ran a binary in every build.
  - `Package.resolved` is committed.
  - The one prebuilt binary in the tree is checked against upstream's
    file, and its hash is recorded.
  - `release.sh` refuses an uncommitted tree or an untagged HEAD.

**The signing key.** Not code, but the most serious finding of the day.
The Developer ID key sat in the login keychain where `codesign` could use
it without a prompt, so anything running as the owner could sign — and
notarize — as the owner's team. That includes a bundle matching the
release app's designated requirement, and with it Atelier's privacy
grants. The identity and the notary credentials moved to a keychain of
their own, locked except while `release.sh` runs. The notary API key had
also sat on disk; it was rotated.

## Verified

A background test instance (`open -g`, its own state directory, the live
app frontmost throughout) restored a hand-written legacy `session.json`:

- **Restore.** A remote session ahead of the active tab, a remote-only
  window and a session with `../../../../etc/passwd` as its id were all
  left behind, and the right tab came back active.
- **Traps held.** In a fixture repo whose config named an fsmonitor
  program and a clean filter, and which shipped `.venv/bin/python` and
  `.venv/bin/node`, nothing ran while the folder was untrusted. Touching
  a file reloaded the tree without running git status.
- **Trust opened the gate.** Adding the folder to the test Claude record
  turned it on within about five seconds: git status ran (fsmonitor still
  off), the open `main.py` got its server, and the venv's python ran. Its
  node never did.
- **Permissions.** The state directory was tightened to 0700, the socket
  was 0600, and the saved files were 0600 after quit.
- **Stall.** A probe sent behind a silent client answered in 0.17s.
- **Descriptors.** A restored shell held only its own terminal.

## Left open

- **A git-aware shell prompt is the same exposure.** The trap fired once
  in the test — from starship, drawing the shell's prompt in the fixture,
  not from Atelier. starship applies a repository's filters itself. That
  lives in the dotfiles.
- **Dev builds** are self-signed with a key `codesign` can use silently,
  without hardened runtime, and under the release bundle id, so TCC grants
  move to whichever build ran last. A distinct dev bundle id is the main
  lever; it splits dev and release settings, so it's the owner's call.
