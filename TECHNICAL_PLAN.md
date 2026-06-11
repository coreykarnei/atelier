# Atelier — Technical Plan

The planning companion to [VISION.md](VISION.md). `VISION.md` is the authoritative
spec for *what* Atelier is and what it deliberately is not; this document records
*how* it gets built — the load-bearing technical decisions, the components, and the
order in which they ship.

**Status: Milestones 0 and 1 built; Milestone 2 (the editor) is next.** M0 proved
the bet (see the [M0 devlog](docs/devlog/2026-06-01-milestone-0.md)); M1 built the
workspace around it (designed in [docs/MILESTONE_1.md](docs/MILESTONE_1.md), built
per the [M1 devlog](docs/devlog/2026-06-10-milestone-1.md)). Decisions marked
**[LOCKED]** are committed and should not be relitigated without revisiting the
vision. The **[CANDIDATE]** picks were validated in the spike (SwiftTerm held).
The former **[OPEN]** questions are all resolved in §6.

---

## 1. The reframe that makes it tractable

Atelier *looks* like "an editor + a shell + an agent," but mechanically it is three
things, and naming them correctly is what keeps scope honest:

1. **Two PTY-backed terminal panes.** Both the shell *and* Claude Code are terminal
   programs. Claude Code is a Node TUI that, per the vision, runs **unchanged, as a
   hosted process**. Atelier spawns the `claude` binary in a pseudo-terminal and
   renders it. We do **not** build a chat UI, an MCP client, or an agent loop.
2. **One non-terminal code editor.** The editor pane is the only one of the three
   that is not a terminal program. It is also the largest body of original work.
3. **A native shell around all of it** that owns the window, chrome, clipboard,
   keyboard focus, and notifications.

The central technical insight: the entire thesis — truthful copy, one clipboard,
real notifications, native blur — is achievable **because Atelier owns the PTY and
the terminal emulator itself**, instead of delegating to tmux. tmux stores a
character *grid* and discards wrap-intent; that is the root cause of the
soft-wrap-fragment copy bug. When Atelier owns the emulator, it keeps the
distinction between a hard newline and a soft wrap, so copy reconstructs logical
paragraphs. **The terminal-emulator layer Atelier owns is the load-bearing
component — not the editor.**

---

## 2. High-level decisions

### 2.1 Substrate: all-native Swift / AppKit **[LOCKED]**

Atelier is a native macOS app written in **Swift**, using **AppKit** for the window,
panes, split view, and chrome (with SwiftUI permissible for self-contained leaf
views where it doesn't fight us). This is the spec-true path: the vision describes
Atelier as the *native successor* to a terminal stack, and native ownership of
chrome, clipboard, selection, blur, and notifications is the reason the app exists.

**Considered and rejected:**

- **Tauri (Rust + web frontend).** Tempting because it hands us a VSCode-shaped
  editor for free (CodeMirror 6 / Monaco) and xterm.js for terminals. Rejected
  because it is a webview: native clipboard/selection ownership becomes muddy,
  blur/vibrancy is a fight, and it quietly betrays the "native successor" framing.
  It would pay part of the friction tax in a different currency.
- **Electron.** Rejected outright — it is the heavyweight, non-native thing the
  whole project exists to escape.

**Accepted cost:** the code editor will not match Monaco's decade of polish. The
vision explicitly does not ask for a VSCode clone — it asks for an editor that
*doesn't fight common editing instincts*. We build the instincts, not the feature
surface. See §2.6 and §3.3.

### 2.2 Claude Code runs as a hosted, unchanged process **[LOCKED]**

The agent pane hosts the real `claude` binary in a PTY. Atelier is its **host, not
its substitute**. We do not reimplement the agent loop, its tools, or its skills,
and we do not parse its **live UI / terminal stream** to build richer affordances in
v1. This is both a vision constraint and a large scope-saver.

**Refinement (Milestone 0 spike, 2026-06-01).** The original wording was "do not
parse its output." The spike proved that truthful copy of *agent* text — a core
VISION promise — is impossible from the terminal grid alone: Claude Code's Ink TUI
hard-wraps and gutters its text before it reaches the PTY, destroying logical-line
structure. The only lossless source is Claude's own persisted transcript
(`~/.claude/projects/<cwd>/<session>.jsonl`). We therefore **narrow** the rule:
*do not parse its live UI/terminal stream; reading its persisted transcript for host
features (e.g. truthful copy) is allowed.* This keeps the spirit — we never scrape or
reimplement the agent's interface — while letting the vision's copy promise ship.
See §3.6.

### 2.3 Notifications via Claude Code hooks, not escape-sequence sniffing **[LOCKED]**

"The agent talks to the OS directly" is implemented through Claude Code's **hook
system**, not by intercepting the terminal bell or OSC sequences. The author's
`dotfiles` already merge a `claude/hooks.json` fragment that fires audible/visual
"done" and "input-needed" signals. In Atelier, the `Stop` and `Notification` hooks
instead invoke a tiny native bridge (a CLI helper that posts a
`UNUserNotification`, or writes to a local socket the app listens on). This is
clean, robust, and literally the vision's intent.

### 2.4 Fixed three-pane layout, one window **[LOCKED]**

Editor top-left, shell bottom-left, agent on the right. The layout **is** the IDE.
Implemented as a fixed `NSSplitView` arrangement, not arbitrary user-created splits,
not a window manager, not a general multiplexer. Atelier manages exactly these three
panes. (Non-goal per vision: arbitrary splits.)

### 2.5 Keyboard-first, with a command palette **[LOCKED]**

Pane focus, the fuzzy file picker, repo-wide search, and a command palette are all
reachable from the home row, pointer optional. A central keyboard-focus manager owns
the focus ring; a command palette is the discoverable surface for every action.

### 2.6 The editor is VSCode-shaped, built natively **[LOCKED]**

Insert-mode default, drag-select, multi-cursor, repo-wide search with a results
panel, fuzzy file picker on a single chord. Built on native text views + tree-sitter
+ an LSP client (see §3.3). Not Helix (modal), not a VSCode clone.

### 2.7 Worktrees are first-class **[LOCKED]**

Spawning, listing, returning to, and tearing down an isolated branch workspace are
one visible action each — a direct port of the `ide -b` / `ide -rm` behavior. Each
worktree is a session root.

### 2.8 Sessions survive restart **[LOCKED]**

Reopen Atelier and the repo, active worktree, per-pane working directories, open
files, focus, and scroll positions are restored to where they were left.

### 2.9 Aesthetic is a spec requirement **[LOCKED]**

Catppuccin Mocha, transparent, native blur (`NSVisualEffectView`). Treated as a
requirement, not decoration. The editor's tree-sitter theme, the terminal palettes,
and the chrome all share one Catppuccin Mocha definition.

### 2.10 macOS-first **[LOCKED]**

No cross-platform abstraction layer on day one. Linux is plausible later; Windows is
out of scope. Do not introduce portability indirection that costs us native fidelity.

---

## 3. Components

Each component lists its **responsibility**, **candidate implementation**, and
**notes/risks**. All library picks are **[CANDIDATE]** — to be validated or replaced
during Milestone 0 (the spike).

### 3.1 Application shell & window
- **Responsibility:** the single window, the fixed three-pane `NSSplitView`, the
  title/chrome, blur/vibrancy, app lifecycle, and global menu.
- **Candidate:** AppKit, `NSWindow` + `NSSplitViewController`, `NSVisualEffectView`
  for blur. Swift Package Manager (SwiftPM) app target.
- **Notes:** owns the Catppuccin Mocha theme tokens that every other component reads.

### 3.2 Terminal emulator layer (shell pane + agent pane)
- **Responsibility:** spawn and host PTY-backed processes (`$SHELL`; `claude`),
  render the terminal grid, manage scrollback, and — critically — own the selection
  model with wrap-intent preserved (see §3.6, truthful copy).
- **Candidate:** **SwiftTerm** (mature Swift terminal emulator, used in shipping
  apps). Two instances, one per pane.
- **Notes / risk:** must verify SwiftTerm renders full-screen TUIs faithfully —
  Claude Code's UI specifically, and incidentally `vim`/`hx` if shelled into. This
  fidelity check is a primary goal of the spike. If SwiftTerm falls short, fallback
  is to evaluate a fork or an alternative emulator core.

### 3.3 Code editor
- **Responsibility:** open/edit/save buffers; syntax highlighting; multi-cursor;
  drag-select; insert-default editing; find/replace; go-to-definition and
  diagnostics.
- **Candidate:** native text view on **TextKit 2** — evaluate **CodeEditSourceEditor
  / STTextView** as the base; **tree-sitter** for highlighting; an **LSP client**
  (JSON-RPC over stdio to sourcekit-lsp/gopls/pyright/etc.) for navigation and
  diagnostics. The open-source **CodeEdit** project is prior art and a borrow-source
  for multi-cursor, find/replace, and picker behavior.
- **Notes / risk:** this is ~70% of the original engineering and the long pole.
  Multi-cursor + LSP + search on TextKit 2 is months, not weeks. It is the largest
  effort but the *lowest uncertainty* — we know it's possible — so it is sequenced
  after the thesis is proven (see §4).

### 3.4 Fuzzy file picker
- **Responsibility:** open any file in the repo from a single chord; respects
  `.gitignore`.
- **Candidate:** repo walk honoring `.gitignore` + a fuzzy matcher (e.g. an fzf-style
  scoring algorithm implemented in Swift, or shelling to `fd`/`rg --files`).
- **Notes:** shares the results-list UI idiom with repo-wide search (§3.5).

### 3.5 Repo-wide search + results panel
- **Responsibility:** search the repo, render hits in a navigable results panel,
  jump to a hit in the editor.
- **Candidate:** shell out to **ripgrep** (`rg --json`), parse and render results.
- **Notes:** native results panel, keyboard-navigable, opens into §3.3.

### 3.6 Truthful copy / unified selection & clipboard
- **Responsibility:** one clipboard and one selection model across all three panes;
  copy returns the *actual* text — paragraphs as paragraphs, no soft-wrap fragments,
  no agent gutter-indent leaking in.
- **Candidate:** in the terminal layer (§3.2), store wrap-intent in the grid model so
  selection reconstructs logical lines; route all copy through one
  `NSPasteboard`-backed path shared by terminal panes and editor.
- **Notes:** **this is the single feature that justifies the project.** Build and
  prove it in the spike. If truthful copy doesn't feel right, the thesis is wrong.

### 3.7 Notification bridge
- **Responsibility:** turn agent events ("finished", "needs input") into real macOS
  notifications.
- **Candidate:** a small native helper invoked by Claude Code's `Stop` /
  `Notification` hooks — either a CLI that posts a `UNUserNotification`, or a local
  socket/IPC the running app listens on so notifications can carry focus actions
  (e.g. "click to focus the agent pane").
- **Notes:** ties directly to the existing `dotfiles` hook pattern (§2.3).

### 3.8 Worktree manager
- **Responsibility:** spawn / list / return-to / tear-down isolated branch
  workspaces, one visible action each; each worktree is a session root.
- **Candidate:** git plumbing (`git worktree add/list/remove`) behind a native UI;
  port the semantics of `ide -b <branch>` and `ide -rm <branch>`.
- **Notes:** decide worktree storage location — mirror dotfiles'
  `~/.local/share/worktrees/` or keep repo-local. **[OPEN]** (see §6).

### 3.9 Session persistence
- **Responsibility:** serialize and restore layout state across restarts.
- **Candidate:** serialize `{repo path, active worktree, per-pane cwd, open files,
  focus, scroll positions}` to disk (JSON or a small store); restore on launch.
- **Notes:** must interact correctly with the worktree manager — a restored session
  may point at a worktree; decide behavior if it was torn down out-of-band.

### 3.10 Keyboard / focus manager & command palette
- **Responsibility:** own the focus ring across panes; route global chords; expose
  every action through a searchable command palette.
- **Candidate:** a central key-handling layer above the panes; a palette view sharing
  the fuzzy-match idiom from §3.4.
- **Notes:** defines the home-row keymap. The keymap itself is **[OPEN]** (§6).

---

## 4. Build plan

Sequenced to **prove the thesis before building the long pole**. The editor (§3.3)
is the biggest piece but the least *uncertain*; the risky, project-defining bet is
the native-terminal-ownership thesis. So that comes first.

### Milestone 0 — The spike (prove the bet) ✅ (built 2026-06-01)
**Goal:** validate that owning the terminal makes truthful copy and native
notifications feel right, and that SwiftTerm renders Claude Code faithfully.
1. SwiftPM macOS app target; a single native window.
2. Two SwiftTerm panes: one spawns `$SHELL`, one spawns the `claude` binary in a PTY.
3. Implement **truthful copy** (§3.6) — selecting an agent paragraph yields clean,
   logical text.
4. Wire a Claude Code `Stop` hook → native notification via the bridge (§3.7).
5. **Verify SwiftTerm fidelity** on Claude Code's full-screen TUI.

**Exit criterion:** selecting an agent paragraph copies clean text and the "done"
ping feels native. If yes, the premise holds and we commit to the long road. If no,
revisit §2.1 / §3.2 before writing more.

### Milestone 1 — The shell becomes a workspace ✅ (built 2026-06-09/10)
1. Fixed three-pane `NSSplitView` layout (editor pane can be a placeholder).
2. Worktree manager (§3.8): spawn / list / return / tear-down.
3. Session persistence (§3.9): panes, cwds, active worktree survive restart.
4. Keyboard focus manager (§3.10): home-row pane focus; a minimal command palette.

As built it grew beyond this list — projects as native tabbed windows, sessions
as tabs, the Landing/promote flow, the `atelier` CLI, per-tab agent state, and
the M3 click-to-focus affordance pulled forward. `docs/MILESTONE_1.md` is the
as-built record.

### Milestone 2 — The editor, incrementally
Each step is independently useful and shippable in order:
1. Open / edit / save a buffer with tree-sitter highlighting.
2. Fuzzy file picker on one chord (§3.4).
3. Repo-wide search + results panel (§3.5).
4. Multi-cursor + drag-select + find/replace.
5. LSP client: go-to-definition, diagnostics (§3.3).

### Milestone 3 — Polish to spec
1. Catppuccin Mocha across editor theme, terminal palettes, and chrome.
2. Transparency + native blur.
3. Command palette completeness; full home-row keymap.
4. Notification affordances (click-to-focus the relevant pane).

**Definition of done (from VISION.md):** a four-hour morning on a fresh worktree
without once thinking about the tool — no escape-sequence hack, no double-copy
cleanup, no shell-script branch dance, no "which pane has focus."

---

## 5. Risks

1. **The editor is a real editor.** Multi-cursor + LSP + search on TextKit 2 is
   months of work. CodeEdit reduces it but does not erase it. Mitigation: sequence it
   after the thesis is proven; ship its sub-features incrementally.
2. **SwiftTerm fidelity for full-screen TUIs.** Claude Code's UI must render
   perfectly. Mitigation: this is an explicit Milestone 0 exit check; fork/alternative
   is the fallback.
3. **Hosting Claude Code as a pure TUI** caps how rich the agent pane can be
   (no clickable diffs / inline approvals). Mitigation: this is *out of scope for v1*
   by design — resist the temptation to parse its output.
4. **TextKit 2 maturity / edge cases** for very large files or unusual encodings.
   Mitigation: validate during Milestone 2.1.

---

## 6. Open questions

All five were resolved in the Milestone 1 design pass (2026-06-09). See
[docs/MILESTONE_1.md](docs/MILESTONE_1.md) §11 for the full rationale.

- **[RESOLVED] Worktree storage location** — `~/.local/share/worktrees/`, mirroring
  `ide`, anchored to the primary tree (keeps worktrees outside the repo so picker /
  search / status never trip on them). (§3.8 · MILESTONE_1 §6)
- **[RESOLVED] The home-row keymap** — defined: `⌃⌘+hjkl` pane focus, `⌘⇧[ ]` /
  `⌘T` / `⌘W` sessions, `⌘P` / `⌘⇧P` / `⌘⇧F` picker / palette / search, `⌘/⌥+arrows`
  reserved to the focused pane. (§3.10 · MILESTONE_1 §5)
- **[RESOLVED] Session-restore vs torn-down worktree** — validate every root on
  restore; an invalid one is surfaced, never silently dropped, reparented, or
  resurrected (non-silent drop + fan re-creation; Claude conversation recoverable
  from `~/.claude`). (§3.9 · MILESTONE_1 §9.1)
- **[RESOLVED] Notification bridge transport** — the socket the app listens on
  (settled in M0). Per-tab attention state reuses it. (§3.7 · MILESTONE_1 §7.1)
- **[RESOLVED] Multi-repo / multi-window** — single application, one window per
  project, sessions as tabs. Not single-workspace; not multi-application.
  (MILESTONE_1 §2)
