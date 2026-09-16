# Atelier

<img src="Resources/AppIcon-1024.png" width="128" align="right" alt="">

A native macOS workspace for agent-assisted coding: an editor, a shell, and
**Claude Code** composed side-by-side in one app that owns its own chrome,
keyboard, clipboard, and notifications — replacing a Ghostty + tmux + Helix +
Claude Code stack that worked, but leaked.

**State: v1.0.0.** The workspace, the editor, remote sessions and the polish
pass are built. Atelier is the author's daily driver.

- **Projects are tabs of one window; sessions are tabs within them** — each
  session a fixed pane shape (editor / shell / agent) hosting its own unchanged
  `claude` process, its tab titled live from Claude's own session summary.
- **A real editor** — TextKit 2 buffer with tree-sitter highlighting in the
  Catppuccin palette (twenty grammars, queries tuned by hand), a file
  explorer with search (files and ripgrep text in one list), `⌘P` go-to-file,
  multi-cursor with VSCode chords, LSP go-to-definition and diagnostics
  (Swift out of the box; the first installed server wins for Python,
  TypeScript, Rust, Go, C/C++, Ruby and more), autosave, markdown preview.
- **Truthful copy** — selecting agent text yields clean logical markdown,
  reconstructed from Claude's persisted transcript (the Milestone 0 bet).
  Terminal panes have clipboard parity with Ghostty: copy-on-select, OSC 52.
- **Worktrees are first-class** — starting a session asks which worktree; tabs
  group into folders named for their worktree; an `atelier` CLI (`atelier`,
  `-b <branch>`, `-rm <branch>`) ports the `ide` script's semantics.
  Worktrees live at `~/.local/share/worktrees/`.
- **Remote sessions** — a session can live on an ssh host, both panes riding
  `tmux` on the far side so the work survives link death and app quits.
- **Sessions survive restart** — the window→session tree snapshots on quit;
  agents resume their conversations (`claude --resume`).
- **The agent talks to the OS** — hook-driven notifications carry the session
  id: banners click through to the exact tab, and tabs wear the agent's live
  state (working / waiting / blocked / unseen-done); the Dock badge counts
  the sessions waiting on you.
- **Catppuccin Mocha, transparent, native blur** — the aesthetic is a spec
  requirement, not decoration.

Built for one developer, on purpose. The design will not bend to generalize —
see [VISION.md](VISION.md) (the what and why), [TECHNICAL_PLAN.md](TECHNICAL_PLAN.md)
(the how and the milestones), [docs/POLISH_PLAN.md](docs/POLISH_PLAN.md) (the
design rules), and [docs/devlog/](docs/devlog/) (how it actually went).

## Running it

Requirements: macOS 14+, Xcode command-line tools (Swift 6 toolchain), and
[Claude Code](https://claude.com/claude-code) on your `PATH` as `claude`.
Optional: `rg` for text search, and whichever language servers you already
have on your login-shell `PATH` (`pyright`, `typescript-language-server`,
`rust-analyzer`, `gopls`, `clangd`…); `sourcekit-lsp` ships with Xcode.

```sh
make run          # build, bundle, launch .build/Atelier.app
make install      # symlink it into /Applications for Spotlight and the Dock
make install-cli  # symlink the `atelier` CLI into ~/.local/bin

make bundle CONFIG=release   # optimised build
```

Notifications need a real `.app` launch and a one-time permission grant. To
let the agent drive tab state and banners, merge
`Resources/hooks/atelier-hooks.json` into `~/.claude/settings.json`. To stop
macOS re-asking for permissions on every rebuild, create the stable
self-signed identity once with `Scripts/make-signing-cert.sh`.

## Layout

```
Sources/Atelier        the app (AppKit)
Sources/AtelierIPC     socket/message contract shared with the CLIs
Sources/atelier-notify hook helper Claude Code calls
Sources/atelier-cli    the `atelier` worktree CLI
Sources/atelier-hlcheck highlight-query harness (Scripts/hlcheck/README.md)
Vendor/                SwiftTerm and the CodeEdit packages, each carrying
                       Atelier's patches (listed in its ATELIER.md)
```
