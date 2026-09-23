# Setting up Atelier

## Local build

Use an Apple Silicon Mac with macOS 14 or later, a Swift 6 toolchain, Xcode
command-line tools, and Git. The bundle script currently looks for the arm64
build output; an Intel or universal bundle is not covered by these instructions.

Install and authenticate Claude Code separately. Atelier hosts the installed
`claude` executable; it does not include Claude Code or access to its service.

From your checkout:

```sh
swift --version
claude --version
make run
```

For an optimized local build:

```sh
make bundle CONFIG=release
open .build/Atelier.app
```

`make install` links `/Applications/Atelier.app` to this checkout's build.
`make install CONFIG=release` builds and links an optimized version. Moving or
removing the checkout breaks that link; rebuilding updates the app it points to.

## Notification hooks

Hooks let Claude Code report working, waiting, blocked, and completed states to
Atelier. Launch the bundled `.app` and allow notifications when macOS asks.

1. Run `make install` so `/Applications/Atelier.app` points to your build.
2. Back up `~/.claude/settings.json` if it already exists.
3. Merge the `hooks` entries from
   [atelier-hooks.json](../Resources/hooks/atelier-hooks.json) into that file.
   Preserve existing settings and hooks; do not replace the entire file or
   create a second top-level `hooks` key.
4. If the app is installed elsewhere, update each helper command path in the
   example to match it. Start a new Claude session to check the setup.

The helper used by the example is
`/Applications/Atelier.app/Contents/MacOS/atelier-notify`.

Upgrading from before 2026-09-23: the `PostToolUse` / `PostToolUseFailure`
entries call the helper with `tool`, which older helpers read as `stop` (a
"Claude finished" banner after every tool call). Build and install the new
app *before* merging those two entries.

If banners are missing, check Atelier's permissions in macOS System Settings
→ Notifications. If session indicators do not update, check that the helper
path exists and that the hook entries are in Claude's settings.

## Worktrees and the CLI

Enable **Settings → Enable worktrees** to choose or create a worktree when
starting a session. Worktrees live under `~/.local/share/worktrees/`.

The optional CLI is installed with:

```sh
make install-cli
```

Add `~/.local/bin` to your shell's `PATH` if it is not already there. With
Atelier running, use `atelier` from a repository, `atelier -b <branch>` for a
branch workspace, or `atelier -rm <branch>` to request worktree removal.

## Search and language support

Install `rg` (ripgrep) for text search; the search implementation falls back
to `git grep` when ripgrep is unavailable. Syntax highlighting does not require a language
server. Navigation and diagnostics depend on a suitable server and project setup.

Atelier discovers supported language servers through the login-shell `PATH`.
Examples include `pyright-langserver`, `typescript-language-server`,
`rust-analyzer`, `gopls`, and `clangd`. Swift uses `sourcekit-lsp` through `xcrun`.
See [LSP.swift](../Sources/Atelier/LSP.swift) for the supported candidates and
selection order. Install language servers separately.

## Remote sessions

Configure and test SSH access to the host first. The remote host needs tmux and
Claude Code; the notification bridge also uses Python 3. Choose a host from the
landing screen or enter `host:directory`.

Remote sessions use a dedicated Atelier tmux server. Atelier writes its tmux
configuration under `~/.config/atelier/` on the host. The notification bridge
installs a helper and merges Atelier hooks into the host's Claude settings;
see [the provisioning script](../Resources/remote/provision.sh) for the exact
changes.

Quitting Atelier leaves remote tmux sessions running so they can reconnect.
Closing a remote session explicitly tears down its associated tmux sessions.
The local editor, file search, and worktree tools are not offered in remote sessions.

## Local state and development signing

Workspace restoration data is stored at `~/.local/state/atelier/session.json`.
Claude Code manages its own authentication and conversation files. Avoid
including these files in public bug reports; use a small reproduction instead.

For repeated development builds, `Scripts/make-signing-cert.sh` creates and
trusts a self-signed code-signing identity in your login keychain. It is optional
and intended to help permissions persist across rebuilds. Read the script before
running it. It is not Developer ID signing or Apple notarization.
