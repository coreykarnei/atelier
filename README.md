# Atelier

A native macOS workspace for agent-assisted coding: an editor, a shell, and
**Claude Code** composed side-by-side in one app that owns its own chrome,
keyboard, clipboard, and notifications — replacing a Ghostty + tmux + Helix +
Claude Code stack that worked, but leaked.

**State:** the workspace is built; the editor pane is next.

- **Projects are tabs of one window; sessions are tabs** within them — each
  session a fixed pane shape (editor / shell / agent) hosting its own unchanged
  `claude` process, its tab titled live from Claude's own session summary.
- **Truthful copy** — selecting agent text yields clean logical markdown,
  reconstructed from Claude's persisted transcript (the Milestone 0 bet).
- **Worktrees are first-class** — a fan off the project pill and an `atelier`
  CLI (`atelier`, `-b <branch>`, `-rm <branch>`) port the `ide` script's
  semantics; worktrees live at `~/.local/share/worktrees/`.
- **Sessions survive restart** — the window→session tree snapshots on quit;
  agents resume their conversations (`claude --resume`).
- **The agent talks to the OS** — hook-driven notifications carry the session
  id: banners click through to the exact tab, and tabs wear the agent's live
  state (working / waiting / blocked / unseen-done).
- **Catppuccin Mocha, transparent, native blur** — the aesthetic is a spec
  requirement, not decoration.

Built for one developer, on purpose. The design will not bend to generalize —
see [VISION.md](VISION.md) (the what and why), [TECHNICAL_PLAN.md](TECHNICAL_PLAN.md)
(the how and the milestones), and [docs/devlog/](docs/devlog/) (how it actually went).

```sh
make run          # build, bundle, launch
make install-cli  # symlink the `atelier` CLI into ~/.local/bin
```
