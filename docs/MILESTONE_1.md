# Atelier — Milestone 1 Plan: "the shell becomes a workspace"

The design companion to [TECHNICAL_PLAN.md](../TECHNICAL_PLAN.md) §4 (Milestone 1).
[VISION.md](../VISION.md) is the authoritative *what*; TECHNICAL_PLAN records the
*how* and the milestone sequence; this document is the resolved design for
Milestone 1 specifically — the workspace model, the chrome, the keymap, and the
build order — settled in a design pass on 2026-06-09.

**Status: designed, pre-implementation.** Milestone 0 (the native two-pane spike)
is complete and committed. Decisions here marked **[LOCKED]** were settled in the
design pass and should not be relitigated without revisiting the vision.
**[DEFERRED]** items are designed but intentionally built later. The §6 open
questions from TECHNICAL_PLAN that this milestone forced are resolved in §11.

---

## 1. What Milestone 1 delivers

Milestone 0 proved the bet: owning the terminal natively buys truthful copy and
real notifications. Milestone 1 turns that two-pane spike into a **workspace** —
the thing you actually live in all day. Concretely, it adds:

- The **fixed three-pane shape** (editor TL, shell BL, agent R) plus a second
  layout mode, with per-session sizing that survives restart.
- **Projects as windows and sessions as tabs** — the native successor to your
  Ghostty-tabs-of-repos / tmux-windows-of-sessions hierarchy.
- A **first-class worktree manager** — spawn/list/return/tear-down, one action
  each, plus an `atelier` CLI that preserves the `ide -b` muscle memory.
- **Session persistence** — repos, sessions, worktrees, panes, and layout return
  where you left them.
- A **keyboard-first command surface** — home-row focus and navigation, a command
  palette as the discoverable backstop.

The editor pane is a **placeholder** through Milestone 1; the real editor is
Milestone 2.

---

## 2. The workspace model **[LOCKED]**

The baseline (the `ide` script + Ghostty + tmux) has two levels of multiplicity,
and Atelier preserves both rather than flattening them:

- **Project = a native window.** One `NSWindow` per repo. A single Atelier
  *application* owns N windows (the standard Mac multi-window document model — one
  process, many windows, like Preview). This is **not** the "window manager" the
  vision rejects: that rejection is about arbitrary splits *inside* a workspace,
  not about how many top-level document windows exist.
- **Session = a tab inside a window.** One session is one instance of the fixed
  pane shape, bound to a `(repo, worktree, per-pane cwd)` root, hosting one Claude
  Code process. Multiple sessions can share a root — this is the "2–3 Claude
  sessions on `main` plus one on a worktree" pattern, ported directly.

**Worktree = codebase identity.** Git enforces that a branch is checked out in at
most one worktree at a time, so `branch → worktree` is one-to-one. The worktree is
therefore *the* unit of codebase isolation: sessions on the same worktree share
files on disk; sessions on different worktrees are isolated. This property is what
lets the bottom bar communicate sharing without ambiguity (§7).

**Why windows-not-tabs for projects:** mapping projects to OS windows hands the
project-switching problem to macOS, which already solves it better than a custom
tab row — `⌘`` to cycle, Mission Control to see all, Spaces to separate by
context, and native window tabbing if you ever want them collapsed into one frame.
The always-visible project row the author wanted is delivered by putting project
tabs **in the titlebar** (§4), at zero extra vertical cost.

### 2.1 The Landing (added during M1.2)

A session does not start as the full pane shape — it starts as a **Landing** and
is **promoted** into an IDE session:

- **`⌘T` opens a Landing tab:** a compact recents list (recent roots + git repos
  in the default folder) over a plain terminal. No editor, no Claude — a Landing
  *is* the "just a terminal" tab, useful as-is forever; promotion is optional.
- **Two promote paths, same result:** pick a recent (`↩` / double-click), or
  `cd` anywhere in the landing terminal and hit **`⌘↩` ("Open IDE Here")** — the
  session transforms *in place* into the Triptych rooted there: the shell
  re-roots (send-keys `cd`, the `ide` script's own move), Claude spawns with the
  pinned session id, the pill picks up the branch.
- **Claude only ever spawns on promote**, rooted in a real project — there is no
  "claude running in a junk default cwd," which also shrinks the TCC prompt
  surface.
- **Promotion is one-way.** To go elsewhere, open a new Landing (`⌘T` is two
  keys). App/project-window open with no restored session lands on a Landing.
- The landing terminal is **focused by default** (terminal-first); the list is
  one `⌃⌘k` away.

---

## 3. Layouts **[LOCKED]**

Two **fixed, named** layout modes — not arbitrary splits (that guardrail keeps
this on the right side of "not a general multiplexer"):

1. **Triptych** — editor TL, shell BL, agent R (the canonical shape).
2. **Split** — agent top, shell bottom, full width; **editor hidden**.

Rules:

- **Hidden is lossless.** In Split the editor is not torn down — its buffers,
  cursor, and scroll stay in memory. Toggling Triptych → Split → Triptych restores
  it exactly. Editor state is only rebuilt when the *session* closes.
- **Opening a file auto-promotes to Triptych** so the buffer has somewhere to land.
- **Per-session is the only truth.** Each session owns its active mode and its
  divider positions *per mode*, persisted across restart. A brand-new session
  starts from factory defaults (Triptych, default dividers) — no inheritance from
  siblings or a window default.
- **Drag = saved.** Divider positions persist per `(session, mode)` *as you drag* —
  no save gesture. Cycling away and back is lossless.
- **Toggle:** `⌘\` and a corner button in the bottom bar (§7), which doubles as the
  current-mode indicator (the glyph shows which mode you're in).

Implemented as a nested `NSSplitView` (vertical outer: left column | agent;
horizontal inner: editor / shell), with Split collapsing the editor subview.

---

## 4. Window & chrome **[LOCKED]**

- **Single window per project**, fixed pane shape, `NSVisualEffectView` blur,
  Catppuccin Mocha (carried from M0).
- **Project tabs live in the titlebar** (Safari/Ghostty pattern) — always visible,
  zero extra vertical cost. `⌘1..⌘9` focus a project; `⌘`` cycles; a `+` opens a
  repo.
- **Bottom bar** carries the worktree pill, session tabs, and status — full
  anatomy in §7.

---

## 5. Keymap **[LOCKED]**

Hybrid: keep collision-free muscle memory, take command surfaces straight from
VSCode, and move only the bindings that *must* move to stop fighting the editor.

| Action | Chord | Notes |
|---|---|---|
| Focus project N | `⌘1..⌘9` | unchanged from Ghostty today |
| Cycle projects | `⌘`` | free — projects are windows |
| Focus pane (directional) | `⌃⌘ + h/j/k/l` | collision-free; matches tmux `prefix+hjkl` instinct |
| Next / prev session | `⌘⇧]` / `⌘⇧[` | browser/VSCode tab nav |
| New / close session | `⌘T` / `⌘W` | universal tab idiom |
| Toggle layout | `⌘\` | Triptych ↔ Split |
| Fuzzy file picker | `⌘P` | VSCode — locked |
| Command palette | `⌘⇧P` | VSCode — locked |
| Repo-wide search | `⌘⇧F` | VSCode — locked (panel is M2) |
| Word / line cursor moves | `⌘/⌥ + arrows` | **forever the focused pane's content** — never rebound |

The single relearned binding is pane focus (`⌥+arrows` → `⌃⌘+hjkl`) — the one that
*had* to move, because the editor and shell both own `⌥+arrow` for word motion.
Session number-keys (`⌥1..9`) are **dropped** — unused in practice, and dropping
them keeps `⌥+number` free of collisions.

---

## 6. Worktree gesture **[LOCKED]**

Worktrees are first-class: spawn / list / return-to / tear-down, one visible action
each. In the model a worktree session is just a bottom-bar tab whose root is the
worktree path, so this is about *invocation*.

**The worktree fan.** The bottom-left pill (§7) is clickable; clicking fans a list
**upward** (it's pinned to the bottom edge):

- **New worktree at top** — the fan is keyboard-first: click it *or* just start
  typing. Typing a new branch name → "Create worktree for *x*"; a name matching a
  local/remote branch → "Create from *x*."
- **Each row** shows branch, open/closed (is a session live for it?), and
  clean/dirty.
- **Click a row = return-to** — focus that worktree's session if one is open, else
  open one. (It does *not* always spawn a new session — that's the `+`'s job, so
  you don't accumulate duplicates.)
- **`x` on a row = tear-down** — opens a confirmation modal. The modal is
  *informative*: clean → quick confirm; dirty → names what would be lost and
  requires explicit force (surfacing git's own refusal, never a silent `--force`).

**New session** is the `+` at the trailing edge of the session-tab strip — a
deliberate "another session on the current root."

**Storage:** worktrees live at `~/.local/share/worktrees/<repo>/<safe-branch>/`,
anchored to the **primary** working tree (resolved via `git rev-parse
--git-common-dir`), never nested inside a sibling worktree. This mirrors the `ide`
script exactly, and keeps worktrees *outside* the repo tree so the file picker,
search, and `git status` never trip on them.

**The CLI.** A second verb set on the existing `AtelierIPC` socket (the same
pattern `atelier-notify` already proves):

- `atelier` → open/focus the project window for `$PWD`'s repo.
- `atelier -b <branch>` → create-or-reuse the worktree + open a session.
- `atelier -rm <branch>` → remove it (with the dirty guard).

It resolves the target repo from `$PWD` like `ide` does; if the app isn't running,
it launches it first. The terminal entry point survives, native substrate
underneath.

---

## 7. The bottom bar **[LOCKED]**

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ⎇ main │ Fix copy bug · Wire palette  ┃  ⎇ Refactor auth  +    42:7  12:34·Jun09  ⊞ │
└──────────────────────────────────────────────────────────────────────────────┘
  pill        main group (shared)         feat-x group     +   line   clock      toggle
 (switch →)                                                    :col  (blink :)  (corner)
```

**Left — the worktree pill: `⎇ <branch>`.** Shows the active session's live HEAD
branch, which (per §2's one-to-one property) *is* the codebase identity. Clicking
it opens the worktree fan (§6). This is the single home for branch — branch is
**not** repeated in the right cluster.

**Center — session tabs.**
- **Text = the Claude session title** (the same summary `/resume` shows), read live
  from the transcript (`~/.claude/projects/...`) — the M0 transcript-reading path,
  reused. Falls back to the worktree name while a session is still untitled, and is
  **user-renamable** as a hard override.
- **Grouped by worktree** with separators (`┃`); the grouping *is* how codebase
  sharing is shown — we do **not** also append the worktree name to each tab.
- A `·2`/`·3` **counter** appears only as the fallback when two same-root sessions
  are both still untitled.
- **Max-width + ellipsis** per tab (full title on hover) — bounds any one title and
  stabilizes widths so live title changes don't cause jittery reflow.
- **Two-row, group-aware wrap** when the strip fills: whole groups flow to row two,
  never split mid-group; `+` rides the trailing edge of the last row. Hard ceiling
  of two rows — beyond that a `»` overflow affordance, so the bar can't grow into a
  third pane.

**Right cluster** (left→right): `line:col` (editor focus only) · `clock · date`
with a blinking `:` (subtle 1 Hz) · the **layout toggle** in the very corner.
No activity dot — see §7.1.

### 7.1 Per-session attention state **[BUILT]**

The right-side "activity dot" idea was dropped as under-motivated: a global dot
can't say *which* session wants you. The per-session version lives on the
**tabs**, as an always-visible colored dot before the title — color, not symbols,
because the strip is peripheral vision and color reads without fixation:

- **working** (blue) — agent mid-turn (`UserPromptSubmit` hook; tab state only,
  no banner). Shows on every tab, including the active one.
- **needs input** (red) — agent blocked on a question (`Notification` hook).
  Also always visible.
- **finished-since-away** (green) — completed while you were on another
  tab/project (`Stop` hook); clears when you focus the tab (an unread badge —
  a completion you watched happen leaves no badge).

Mechanics: the hooks pipe their stdin payload's `session_id` through
`atelier-notify` onto the M0 socket; the app maps it to the session via its pinned
claude session id. One event, two sinks — the OS banner for "look at the app"
(banner clicks **focus the exact session tab**, the M3 affordance) and the tab
badge for "look at *this* session."
The hooks fragment is merged *alongside* the dotfiles afplay hooks, additively.

---

## 8. The command palette **[LOCKED]**

**Dedicated surfaces, not one omni-bar.** `⌘P` (files), `⌘⇧F` (search), and the
worktree fan are each a one-chord fast path; the palette (`⌘⇧P`) is the
**discoverable backstop** — where "I forget the chord" resolves — not a replacement.

**Placement:** a **centered overlay descending from the titlebar** (VSCode
position), floating above the panes with them dimmed/blurred behind (Catppuccin
blur). `Esc` dismisses; scoped to the focused window. This establishes the surface
rule: **global surfaces = centered overlay from the top** (palette and `⌘P` file
picker are the same component, different content); **control-bound surfaces =
popover from their control** (the worktree fan rises from the pill).

**Contents** — the union of every app action, including navigation verbs, so it
doubles as "go anywhere":

- **Session** — New · Close · Next/Prev · Rename · Switch to… (by title)
- **Worktree** — New… · Switch… · Remove… (open the fan)
- **Project** — Open repo… · Switch to… · Close window
- **View** — Toggle Layout · Focus Editor/Shell/Agent
- **File** — Open… (`⌘P`) · Save · Save All · Search… (`⌘⇧F`) · Go to Line…
- **App** — Reload · About · Quit

Details: category-prefixed for fuzzy grouping (`wt` finds every worktree command);
the **keybinding is shown** on each row (the palette teaches the chords); recents
float to top; `…` routes to the relevant picker/fan. The command set is
**curated and fixed** — no plugin surface, on-spec with "not a general IDE."

(Repo-wide search `⌘⇧F` is a docked **results panel**, not an overlay — Milestone 2.)

---

## 9. Session persistence **[LOCKED]**

Serialize a **list of project windows**, each with its sessions:

```
windows: [
  { repo, sessions: [
      { worktree, layoutMode, dividers: {triptych, split},
        panes: { editor: {openFiles, focus, scroll},
                 shell: {cwd},
                 agent: {cwd, claudeSessionRef} },
        title?, renamed? }
  ], activeSession }
], activeWindow
```

Restore reconstructs windows → sessions → roots, panes, cwds, open files, focus,
scroll, and per-session layout.

### 9.1 The restore edge — orphaned worktree **[LOCKED]**

A restored session may point at a worktree removed out-of-band (a bare-shell
`git worktree remove`, an `rm -rf`, a deleted branch).

**Governing rule: validate every session root on restore. A valid root restores
fully; an invalid one is surfaced — never silently dropped, reparented, or
resurrected.** The three disqualified defaults: silent drop (lost state, no trace),
silent reparent onto `main` (looks fine, is wrong — the conversation was about
another codebase), and auto-recreate (resurrects what you may have deliberately
deleted; impossible if the branch is gone too).

**Chosen behavior — non-silent drop.** On launch, validate each root via git. Valid
sessions restore normally. Orphans don't restore, but a single consolidated notice
names them and why (*"2 sessions weren't restored — their worktrees no longer
exist: `feat-x`, `hotfix`"*). Re-creation flows through the existing worktree fan.

This loses little of real value: an orphaned session's "open files" are already
gone with the worktree, and the one thing worth recovering — the **Claude
conversation** — lives in `~/.claude/projects/...` *outside* the worktree, so
recreating the worktree at the same path and resuming (`claude --resume`) recovers
it. A graceful **dormant-session + inline self-heal** UI (restore broken, offer
one-click recreate when the branch survives) is the noted upgrade if dropping ever
feels too lossy — but not built up front for an edge this rare.

---

## 10. Build sequence

Dependency-ordered; each sub-step is independently useful.

- **M1.1 — Three-pane shell + layout system.** Nested `NSSplitView` (Triptych),
  Split mode, `⌘\` + corner toggle, per-`(session, mode)` divider persistence. Get
  the layout right for a single session before multiplying anything.
- **M1.2 — Sessions within a window.** Bottom-bar tab strip; new/close/switch;
  focus manager (`⌃⌘+hjkl`, session chords); Claude-title labels (reuse M0
  transcript reader); the Landing + promote flow (§2.1); tmux-style bar colors
  (blue pill, green active tab); worktree grouping and two-row wrap follow with
  worktrees (M1.4).
- **M1.3 — Projects as windows.** Multi-window app; titlebar project tabs;
  `⌘1..9` / `⌘``; per-window session state.
- **M1.4 — Worktree manager.** The left-pill fan (list/create/return/remove),
  storage at `~/.local/share/worktrees/`, the dirty-guarded delete, and the
  `atelier` / `-b` / `-rm` CLI over IPC.
- **M1.5 — Session persistence.** Serialize/restore the window→session model
  (§9), including the validate-root edge (§9.1).
- **M1.6 — Command palette.** Centered overlay, the §8 command set, keybinding
  display.

**Deferred within/after M1:** per-session attention state (§7.1) — reuses the M0
hook plumbing; sequence whenever notifications-to-tabs is wanted.

---

## 11. Resolved open questions (from TECHNICAL_PLAN §6)

- **Worktree storage location** → `~/.local/share/worktrees/`, mirroring `ide`,
  anchored to the primary tree. Keeps worktrees outside the repo tree so picker /
  search / status never trip on them (§6).
- **Home-row keymap** → defined in §5.
- **Session-restore vs torn-down worktree** → §9.1 (validate-and-surface,
  non-silent drop).
- **Notification bridge transport** → already settled in M0 (socket the app
  listens on). Per-tab attention state (§7.1) reuses it.
- **Multi-repo / multi-window** → resolved as **single application, one window per
  project, sessions as tabs** (§2). Not single-workspace; not multi-application.

No Milestone 1 open questions remain.

---

## 12. Risks

1. **Tracking the agent pane's active Claude session** for tab titles and attention
   state — if you `/resume` inside the pane, the session id changes. Heuristic:
   most-recently-modified `.jsonl` for the cwd (the same lookup truthful copy
   needs). Confirm the transcript's title field during M1.2.
2. **Live title churn** — Claude rewrites summaries mid-work; tabs need a debounce
   plus the max-width cap (§7) so the strip doesn't twitch or reflow.
3. **Multi-window state coherence** — N windows sharing one process and one
   persistence store; validate that close/restore/worktree-removal stay consistent
   across windows (M1.5).
4. **Editor placeholder honesty** — Milestone 1 ships the editor pane as a
   placeholder; the layout/persistence model must not bake in assumptions that the
   real editor (M2) would have to unwind.
