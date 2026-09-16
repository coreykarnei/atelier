# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

**Milestones 0 and 1 built (M1.1–M1.6 landed); polish pass
(docs/POLISH_PLAN.md) built through all phases — 0 (foundation tokens),
1 (cockpit), 2 (distances), 3 (arrivals), 4 (overlay physiology).** Read `VISION.md` (the
authoritative *what*), `TECHNICAL_PLAN.md` (the *how* and the milestone
sequence), and `docs/MILESTONE_1.md` (the workspace/layout/keymap/worktree/
persistence design, as built) before proposing anything. The polish pass is
planned in `docs/POLISH_PLAN.md` — phased (tokens → cockpit → distances →
arrivals → overlays) and carrying the written design rules (motion inventory,
contrast discipline, no-escalation, two-voice type, latency budget); treat
those rules as binding when touching any UI. Phase 0 landed `Theme.Elevation`
(Catppuccin z-ramp + lighting model), `Theme.Typography` (the two-voice type
system; the plan's `Theme.Type`, renamed — Swift reserves `Type`), and the
`Theme.fieldAlpha` translucency token (fields translucent over the
behind-window blur, text never; opaque under Reduce Transparency).

What exists today:
- A **SwiftPM macOS app** (Swift 6 toolchain, language mode v5) using **AppKit** +
  **SwiftTerm** — vendored at `Vendor/SwiftTerm` (1.13.0 plus Atelier's
  terminal-side patches; `ATELIER.md` there lists them). Terminal decisions
  (wheel routing, cursor, input encoding) go in the vendored copy, never as
  app-side overrides or event monitors, and each patch is meant for upstream. Three targets: `Atelier` (the app), `atelier-notify` (the hook
  CLI), and `AtelierIPC` (shared socket/message contract).
- A **single window** with two PTY-backed SwiftTerm panes — `zsh` (left) and the
  hosted `claude` binary (right) — Catppuccin Mocha palette, native blur.
- A **notification bridge**: a unix-socket listener in the app + the
  `atelier-notify` CLI, invoked from Claude Code `Stop`/`Notification` hooks.

Truthful copy is working in both panes (shell via soft-wrap join; agent via
transcript-aligned markdown — see the M0 devlog).

Milestone 1 (built; see `docs/MILESTONE_1.md`):
- **Projects as tabs of the one workspace window** (`⌘T` new project tab,
  `⌘1..9`, `⌃⇥`/`⌃⇧⇥` cycle, `⌥⌘W` close; since 2026-09-10 Atelier draws its
  own full-width tab row under the titlebar — `WorkspaceWindowController` +
  `ProjectStrip.swift`, replacing native window tabbing — rounded selected
  chip, each tab carrying its sessions' attention marks; `ProjectController`
  owns everything below the row),
  **sessions as bottom-bar tabs** (`⌥⌘T` sibling on the same root; `⌘⇧T` reopens
  the last-closed session; the active tab carries a leading close `×`), each hosting
  its own pinned `claude --session-id` whose transcript `ai-title` labels the tab.
- **The Landing** (§2.1): sessions start as an opener-over-terminal and promote
  in place (pick a repo, or `⌘↩` on the landing terminal's cwd); Claude spawns
  only on promote. Rebuilt 2026-07-13 on the **summon idiom** (`Summon.swift`:
  the shared type-to-choose surface — autofocused field, fuzzy filter, sliding
  highlight — that the command palette also hosts and the M2 `⌘P` picker will):
  a centered raised card, opener-first focus, terminal in the bottom third.
- **Triptych/Split layouts** (`⌘\`), per-session dividers; `⌃⌘+hjkl` pane focus.
- **Worktree manager** (reworked 2026-09-03): the **worktree chooser** — a
  small modal the `+`/`⌥⌘T` raise before a session spawns ("Starting a session
  in worktree [main ▾]", ↩ starts; dropdown lists worktrees + New…; typing
  names a new one), gated behind Settings → Enable worktrees — plus the
  `atelier` / `-b` / `-rm` CLI over the M0 socket (`make install-cli`).
  Tear-down: right-click a worktree folder's label in the tab strip, or the
  palette. The old pill fan is deleted.
- **Session persistence**: window→session tree saved on quit, restored on launch
  with root validation; agents resume via `claude --resume`.
- **Command palette** (`⌘⇧P`).

Also built: per-tab attention state (§7.1 — the agent's exact state, always
visible: blue dot working, peach dot waiting-on-you, peach `!` explicitly
blocked, green dot unseen-completion → waiting on focus; fed by hooks carrying
`session_id`, banner clicks focus the exact session), **worktree folders** in
the tab strip (2026-09-03: each root's tabs sit in a folder-shaped cell whose
label tab names the worktree — `main` / `⎇ dir` / `@host` — stepped lighter/
darker per group off the main folder's colour; two-row group-aware wrap + `»` overflow, overflowed tabs keep their
⎇/attention marks in the menu, and the `»` wears the loudest overflowed
state), a **Settings window** (`⌘,` / the bar's gear: field-opacity slider
applied live via `Settings.didChange`, Enable worktrees), and inline tab rename (double-click edits the title in place — ↩
commits a hard override of the live Claude title, Esc cancels, empty reverts;
titles uncapped).

Milestone 2 (in progress): **M2.1 landed 2026-07-13** — the editor pane hosts a
real buffer (CodeEditSourceEditor / TextKit 2, incremental tree-sitter
highlighting, `Theme.Editor` Mocha syntax palette, background `base` at
fieldAlpha). `⌘O` open / `⌘S` save / dirty-close guard / per-session open-file
persistence. Note: `Vendor/CodeEditSymbols` is a committed local override of an
upstream transitive dep whose manifest only builds under Xcode — see the M2.1
devlog. **M2.2 landed same day** — `⌘P` Go to File: `FilePicker` on the shared
`SummonCardOverlay` (the palette's floating chrome, extracted), `git ls-files`
offer with per-repo recents leading, dirty-buffer guard unified across
close/open. **M2.3 landed same day** — `⌘⇧F` Find in Repo: `RepoSearchOverlay`,
the first externally-filtered summon (debounced rg / `git grep -F` fallback,
capped with an honest tail row, `↩` opens the hit at line:column via
`EditorPane.reveal`). **M2.5 landed 2026-07-14** — the LSP client
(`LSP.swift`: JSON-RPC/stdio to sourcekit-lsp, one per repo root; Swift
buffers only): F12 go-to-definition (same-file reveals, cross-file rides the
⌘P open path) and diagnostics as EmphasisManager underlines (pulled via LSP
3.17 `textDocument/diagnostic` — sourcekit-lsp doesn't push). M2.4
(multi-cursor/find-panel polish) is library-native and awaits an owner
feel-check. **M2.6 landed 2026-09-15** — the file explorer
(`FileExplorer.swift`): a tree of the session root (worktree-aware, `.git`
hidden, gitignored dimmed, FSEvents-refreshed) down the editor pane's left
edge; single click previews (soft-wrapped, read-only), double-click/`↩`
commits and folds the tree to a 26pt rail with a chevron; `⌘B` toggles.

Also landed 2026-07-14: **remote sessions** — the native successor of the
dotfiles' `ide-pi` (see `docs/devlog/2026-07-14-remote-sessions.md`). A
session can live on an ssh host (`Remote.swift`): both panes ride
`ssh -t … tmux new -A` into a host-side `-L atelier` server, so the work
survives link death and app quits; link death (ssh 255) auto-reattaches on
backoff behind the reconnecting placard, ⌘W kills the host-side pair, quit
leaves it running and relaunch reattaches mid-conversation. Entry: hosts
from `~/.ssh/config` in the Landing offer (`host:dir` typed queries inject
a synthetic row). Remote sessions pin Split, skip editor/⌘P/⌘⇧F/worktrees,
wear `@host` on the tab, and group by host. Attention dots cross the wire:
`RemoteLink` provisions a python `atelier-notify` + hook entries onto the
host and holds a dedicated single-flight `ssh -N -R` socket forward (never
through the ControlMaster mux — it reports success and never binds).

Also landed 2026-07-14: the **transparency pipeline** (the owner-reported
opaque-window bug was compositing arithmetic — see
`docs/devlog/2026-07-14-transparency-pipeline.md`; WindowServer blur via CGS
in `WindowBlur.swift`, fieldAlpha 0.75 = Ghostty parity, terminals paint the
wash exactly once) and the **content type scale** (`Theme.TypeScale`,
⌘+/⌘−/⌘0, terminals + editor across all windows, JetBrains Mono at Ghostty's
14pt default; chrome never scales).

## Commands

- `make build` — compile all targets via SwiftPM.
- `make bundle` — assemble `.build/Atelier.app` (Info.plist → bundle id
  `dev.sterlingcore.atelier`, ad-hoc signed; bundles `atelier-notify` too).
- `make run` — build, bundle, and `open` the app.
- `make clean` — `swift package clean` + remove the app bundle.

Notifications need a real `.app` launch (`make run`/`open`) for the bundle identity
UNUserNotification requires — and a one-time permission grant. To enable agent
notifications, merge `Resources/hooks/atelier-hooks.json` into
`~/.claude/settings.json` (same manual-merge pattern as the dotfiles fragment).

## What Atelier is

A single-window, **native macOS** workspace for agent-assisted coding: an editor,
a shell, and **Claude Code** composed side-by-side in one app that owns its own
chrome, keyboard, clipboard, and notifications.

It is the native successor to the author's current terminal IDE — Ghostty + tmux +
Helix + Claude Code, driven by the `ide` script (see `~/CLAUDE.md` and the
`dotfiles` repo). That stack works because terminals compose, but it leaks: too
many processes pretend to be each other and negotiate through escape sequences.
Atelier's thesis is to pay that friction tax **once, in code** — replacing the
four-layer stack with one native app while preserving its composition.

## Architecture intent (the load-bearing constraints)

These are design commitments from `VISION.md`, not yet implemented. Any code
proposal must fit them:

- **Fixed three-pane shape, one window.** Editor top-left, shell bottom-left,
  agent on the right. The layout *is* the IDE — not arbitrary splits, not a window
  manager, not a general multiplexer. It manages exactly these panes.
- **Claude Code runs as a hosted process, unchanged.** Atelier is its *host*, not
  a replacement. Do not reimplement the agent loop, its tools, or skills. The
  agent talks to the OS directly (real notifications) instead of through the
  bell/`afplay`/status-flag chain.
- **Native ownership of chrome, keyboard, clipboard, notifications.** The reason
  the app exists is to stop plumbing these through escape sequences. One clipboard,
  one selection model. Copy from any pane returns the *actual* text (paragraphs as
  paragraphs, no agent gutter-indent leaking in).
- **VSCode-shaped editor, not Helix.** Insert-mode default, drag-select,
  multi-cursor, repo-wide search with a results panel, fuzzy file picker on a
  single chord. Not a VSCode clone — an editor that doesn't fight common editing
  instincts.
- **Worktrees are first-class.** Spawning/listing/returning-to/tearing-down an
  isolated branch workspace is one visible action each (mirrors `ide -b`).
- **Keyboard-first.** Pane focus, picker, search, command palette all reachable
  from the home row. Pointer optional.
- **Sessions survive restart.** Reopen and the repo, worktrees, and panes are
  where they were left.
- **Aesthetic is a real constraint:** Catppuccin Mocha, transparent, native blur.
  Treat it as a spec requirement, not decoration.

## Non-goals (do not propose these)

- Not cross-platform on day one — **macOS-first**. Linux is plausible later;
  Windows is out of scope.
- No language-specific build runners, no plugin marketplace, no settings UI for
  every preference. Scope is strictly: code, shell, agent, side by side.
- Not a general IDE and not a general multiplexer.

## Audience

Single developer, by design. The repo is public, but the design choices **will not
bend to generalize**. When a decision trades broad applicability against fit for
this one workflow, choose fit.
