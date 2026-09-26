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

## Notifications and sounds

Atelier passes its Claude Code hooks to every agent it starts (`claude
--settings`), so there is nothing to merge into `~/.claude/settings.json`.
They report working, waiting, blocked and finished states, and follow a
conversation through `/resume` and `/clear`. A `claude` started outside
Atelier fires none of them. Launch the bundled `.app` and allow
notifications when macOS asks.

**Upgrading from 1.4.2 or earlier:** remove the `atelier-notify` entries you
merged into `~/.claude/settings.json`. If they name a different helper path
than the running app, every event arrives twice.

**Sounds.** Atelier plays Blow when a turn finishes and Tink when Claude
needs you; **Settings → Sounds** turns them off, along with terminal bells
in both panes. If your own Claude settings
play a sound on `Stop` or `Notification` (an `afplay` hook, say), Atelier
stays quiet rather than ring twice, and Settings says so. To keep that hook
for Claude in a plain terminal and let Atelier sound inside the app, make it
step aside when `ATELIER_TAB` is set:

```sh
[ -n "$ATELIER_TAB" ] || afplay /System/Library/Sounds/Blow.aiff
```

If banners are missing, check Atelier's permissions in macOS System Settings
→ Notifications.

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

## Releasing

`make release` builds the zip the Homebrew cask downloads: a release build
signed with the Developer ID (hardened runtime, secure timestamp), notarized
by Apple and stapled, so it opens without the quarantine prompt. It writes
`.build/dist/Atelier-<version>.zip` and prints the sha256 for the cask.

One-time setup, on an Apple Developer Program account:

1. A **Developer ID Application** certificate in the login keychain — Xcode →
   Settings → Accounts → Manage Certificates → **+**.
2. Notary credentials as a keychain profile, from an App Store Connect API key
   (Users and Access → Integrations → Team Keys, Developer access):

   ```sh
   xcrun notarytool store-credentials atelier-notary \
     --key ~/.appstoreconnect/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
   ```

   A 403 "required agreement is missing" means the Program License Agreement
   needs accepting at developer.apple.com — and can take a while to take
   effect once it has been.

`DEVELOPER_ID` and `NOTARY_PROFILE` override the identity and the profile.
Dev builds (`make bundle`) keep the self-signed identity above; after a
release, `make bundle` returns `.build/Atelier.app` to one.
