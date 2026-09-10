# Atelier — Milestone 1 Plan: "the shell becomes a workspace"

The design companion to [TECHNICAL_PLAN.md](../TECHNICAL_PLAN.md) §4 (Milestone 1).
[VISION.md](../VISION.md) is the authoritative *what*; TECHNICAL_PLAN records the
*how* and the milestone sequence; this document is the resolved design for
Milestone 1 specifically — the workspace model, the chrome, the keymap, and the
build order — settled in a design pass on 2026-06-09.

**Status: built (M1.1–M1.6 landed, plus the post-plan refinements; see the
[M1 devlog](devlog/2026-06-10-milestone-1.md)).** This document is kept as-built —
where the implementation deliberately diverged from the original design pass, the
text reflects what shipped. Milestone 0 (the native two-pane spike)
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
- **Two promote paths, same result:** pick a recent (`↩` / single click), or
  `cd` anywhere in the landing terminal and hit **`⌘↩` ("Open IDE Here")** — the
  session transforms *in place* into the Triptych rooted there: the shell
  re-roots (send-keys `cd`, the `ide` script's own move), Claude spawns with the
  pinned session id, the pill picks up the branch.
- **Claude only ever spawns on promote**, rooted in a real project — there is no
  "claude running in a junk default cwd," which also shrinks the TCC prompt
  surface.
- **Promotion is one-way.** To go elsewhere, open a new Landing (`⌘T` is two
  keys). App/project-window open with no restored session lands on a Landing.
- The landing is **opener-first** (revised 2026-07-13, owner; originally
  terminal-first): `⌘T` puts the cursor in a filter field over recents + repos
  — the first keystroke lands, `↩` opens the top match. This is the shared
  *summon idiom* (field + fuzzy filter + sliding highlight, `Summon.swift`),
  the same surface the command palette and the M2 `⌘P` picker use. The shell
  is one `⌃⌘j` away and the hint line says so.
- **Closing everything kicks back to the Launch view, never out of the app**
  (refinement pass): closing the last session tab un-anchors the window into a
  fresh Landing; closing the last project window opens a fresh Landing window.
  Only `⌘Q` quits — which is also the persistence snapshot point (§9).

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
| New project tab | `⌘T` | a Landing — matches Ghostty's new-tab muscle memory (revised during M1.3: the Landing is a *project* opener, so it lives at the project tier) |
| New session (on main) | `⌥⌘T` | sibling session on the project's main checkout |
| Reopen closed session | `⌘⇧T` | resurrects the last-closed session at its old position; the agent resumes its conversation |
| Open IDE here | `⌘↩` | promote a Landing at the terminal's cwd |
| Close session | `⌘W` | last one reverts the window to a Landing |
| Toggle layout | `⌘\` | Triptych ↔ Split |
| Fuzzy file picker | `⌘P` | VSCode — locked |
| Command palette | `⌘⇧P` | VSCode — locked |
| Repo-wide search | `⌘⇧F` | VSCode — locked (panel is M2) |
| Word / line cursor moves | `⌘/⌥ + arrows` | **forever the focused pane's content** — never rebound |

The single relearned binding is pane focus (`⌥+arrows` → `⌃⌘+hjkl`) — the one that
*had* to move, because the editor and shell both own `⌥+arrow` for word motion.
Session number-keys (`⌥1..9`) are **dropped** — unused in practice, and dropping
them keeps `⌥+number` free of collisions.

Revised 2026-07-13 (owner): the active tab grew a leading close `×`, and with a
clickable close comes the browser's undo — `⌘⇧T` now **reopens** the last-closed
session (matching `⌘T`-new / `⌘⇧T`-reopen browser muscle memory exactly);
new-session-on-main moved to `⌥⌘T`.

---

## 6. Worktree gesture **[LOCKED — revised 2026-09-03]**

Worktrees are first-class: spawn / list / return-to / tear-down, one visible action
each. In the model a worktree session is just a bottom-bar tab whose root is the
worktree path, so this is about *invocation*.

**The worktree chooser** (replaces the pill fan, owner call 2026-09-03). Worktree
choice is part of *starting a session*, not a separate surface: the `+` / `⌥⌘T`
raise one small modal before the session spawns —

```
┌─────────────────────────────────┐
│ ×   Starting a session in worktree │
│           ┌───────────┐          │
│           │ main    ▾ │          │
│           └───────────┘          │
│                            [ ↩ ] │
└─────────────────────────────────┘
```

- **Default is the main checkout**, so the fast path is *plus, enter*.
- **The suggestion is the worktree you're in** (2026-09-08), so the fast path
  stays plus-enter wherever you are.
- **The dropdown** unfolds an inline list inside the card (the card grows):
  the repo's worktrees — the primary tagged *main checkout*, every other row
  wearing a hover `×` that removes the worktree behind the guarded modal
  (clean: "anything not pushed is lost with it"; dirty: the real status
  lines, force required) — and **New worktree…**, which swaps the dropdown
  for a name field in place;
  `↩` creates the worktree (existing local/remote branch → checked out; new
  name → branched from `main`) and starts the session in it. Naming a branch
  that already has a worktree simply picks it.
- **Keyboard-first**: `↩` starts, `Esc`/`×`/scrim click dismiss, `↓`/space/tab
  open the dropdown, and *typing any character* jumps straight into naming a
  new worktree with that character typed. `Esc` in the name field steps back
  to the dropdown.
- **Gated in Settings** (`Enable worktrees`, default off): off, the `+` starts
  a session on main with no modal. The `atelier -b` CLI works regardless.
- **Tear-down** lives on the folder (§7): right-click a worktree folder's
  label → *Remove worktree…*; also the palette (`Worktree: Remove ⎇ x…`) and
  `atelier -rm`. The confirmation is *informative*: clean → quick confirm;
  dirty → names what would be lost and requires explicit force (surfacing
  git's own refusal, never a silent `--force`).

*(Superseded: the bottom-left pill fan — filter-or-name field, return-to rows,
`×` per row. The pill is now a static project label.)*

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

## 7. The bottom bar **[LOCKED — revised 2026-09-03]**

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│           ┌ main ┐                       ┌ ⎇ feat-x ┐                               │
│ ┌───────┐ │ Fix copy bug · Wire palette │ │ Refactor auth │  +     12:34·Sep03  ⊞ ⚙ │
│ └atelier┘ └────────────────────────────┘ └───────────────┘                          │
└────────────────────────────────────────────────────────────────────────────────────┘
   pill        main folder (surface0)        worktree folder (lighter/darker)   clock  toggle gear
 (static)
```

**Left — the project pill (static).** The project's name, unchanged across
session switches. Retired for a day (2026-09-07) as a third copy of the repo
name; restored 2026-09-08 — the owner wants an anchor at the bar's left edge,
redundant on purpose. It does nothing on click (the fan is gone, §6).
The bar is controls, not a window-drag handle (`mouseDownCanMoveWindow` is off
across it); the titlebar wash re-speaks the system double-click action (zoom,
or minimize per the user's setting) since the hidden-title titlebar passes
clicks through to it.

**Center — session tabs, in folders.**
- **Text = the Claude session title** (the same summary `/resume` shows), read live
  from the transcript (`~/.claude/projects/...`) — the M0 transcript-reading path,
  reused, against each session's *pinned* `--session-id` so same-root sessions
  never collide. Falls back to the folder name while a session is untitled, and is
  **user-renamable** (double-click) as a hard override. Titles are **uncapped** —
  full text, no ellipsis; the wrap and overflow absorb long ones.
- **Grouped by worktree into folders** (owner call 2026-09-03): each root's tabs
  sit inside a rounded cell with a small **label tab rising from its top-left
  edge** — one continuous shape, one fill, so it reads as a folder, not a box with
  a badge. The label names the **worktree, never the branch** (owner call
  2026-09-07 — folders are places, a branch is a state): `main` for the main
  working tree (git's term; the pill already names the repo), a drawn tree
  silhouette (cloud canopy, forked trunk — the owner's reference) + `dir` for
  a linked worktree, `@host` for a remote group. **One group draws
  no folder chrome** — bare tabs; folders appear when a second group opens.
  Label coats are the folder's body pulled toward mantle and opaque, so the
  label text holds at subtext0 on every rung. Worktree folders share the
  main folder's colour and differ only in **lightness** (owner call
  2026-09-10, replacing the earlier hue tints): the main checkout is plain
  surface0; further folders step outward as they arrive — slightly lighter,
  slightly darker, lighter still, darker still — one family, locked per
  worktree while it is open. No hue is spent here: blue, green, and peach
  already mean anchor, active, attention. Inactive tab titles sit at subtext0,
  the §1.2 cap: over a folder fill, overlay0 fell below legible. **The
  branch is on inquiry**: rest the pointer on a label for ~350 ms and a
  `⎇ branch` chip floats above it, over the pane content the label already
  rises into; nothing in the strip moves; it's gone on exit. (Considered and
  declined: an expanding label — hover reveals never shift text — and the
  active branch in the pill slot — reflows the strip on every session switch
  and speaks for one session only.) A folder cell is never narrower than its
  label. The bar's frame includes the labels' overhang band (transparent,
  pass-through) because AppKit clips hit-tests, tracking, and cursor rects to
  visible bounds. Fills are
  0.6-alpha — the bar's translucency shows through. The per-tab `⎇` glyph is
  gone: the folder *is* the mark (it returns only inside the `»` menu, which has
  no folder). Right-click a worktree folder's label → *Remove worktree…*.
- **Two-row, group-aware wrap** when the strip fills: whole folders flow to row
  two, never split unless one folder alone exceeds a row (then its continuation
  is a bare, labelless cell); `+` rides the trailing edge of the last row. Hard
  ceiling of two rows — beyond that a `»` overflow menu, so the bar can't grow
  into a third pane. The bar stays 30 high: the label tabs **poke up past the
  bar's top edge over the pane content** (owner call 2026-09-07) rather than
  thickening the bar; two rows (72) house the lower row's label band between
  the rows.
- **Drag to arrange** (2026-09-07): drag a session tab along the bar and the
  strip re-flows live around it; it trades places with a sibling once its
  leading edge is a little past the sibling's midpoint. Pushed into a
  neighboring folder it does *not* join it (a session can't change worktree by
  dragging) — the two **folders swap** instead. The folder's label tab is a
  handle: drag it to move the whole group (open-hand cursor on hover; session
  tabs, whose first act is select, wear none). The arrangement is the sessions'
  array order, so it persists. Groups are no longer forced main-first.

**Right cluster** (left→right): `line:col` (editor focus only) · `clock · date`
with a blinking `:` (subtle 1 Hz) · the **layout toggle** · the **settings gear**
(`⌘,`: field opacity slider, Enable worktrees) in the very corner. No activity
dot — see §7.1.

### 7.1 Per-session attention state **[BUILT]**

The right-side "activity dot" idea was dropped as under-motivated: a global dot
can't say *which* session wants you. The per-session version lives on the
**tabs**, always visible — the agent's *exact* state, read peripherally (color
over symbols; the one symbol is reserved for the one urgent state). Once a
session has run it is essentially always either working or waiting:

- **working** (blue dot) — agent mid-turn (`UserPromptSubmit` hook; tab state
  only, no banner).
- **waiting** (peach dot) — turn done, your move. Entered when a completion
  happens on the tab you're watching, when a green tab is focused, or via
  Claude's idle "waiting for your input" ping (classified from the
  `Notification` hook body).
- **needs input** (peach `!`) — agent explicitly blocked: permission or a
  question (the remaining `Notification` hook cases).
- **finished-since-away** (green dot) — completed while you were on another
  tab/project (`Stop` hook); on focus it becomes *waiting*, not nothing — the
  unread mark clears, the fact that it's your move doesn't.

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

Dependency-ordered; each sub-step is independently useful. **All landed**
(commits `202ac7c` → `4a65cdf`), plus a refinement pass after M1.6: static
project pill, `+`-from-main, close-to-Launch-view, the exact-state attention
model, and uncapped tab titles.

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

**Initially deferred, since built:** per-session attention state (§7.1), worktree
grouping + two-row wrap + rename in the strip, and notification click-to-focus
(the TECHNICAL_PLAN §4 M3 affordance, pulled forward).

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
2. **Live title churn** — Claude rewrites summaries mid-work, and titles are
   deliberately uncapped (§7), so a tab can change width mid-session and shift
   its neighbors. Accepted trade at 2–4 sessions; a generous cap is the fallback
   if the strip feels twitchy in practice.
3. **Multi-window state coherence** — N windows sharing one process and one
   persistence store; validate that close/restore/worktree-removal stay consistent
   across windows (M1.5).
4. **Editor placeholder honesty** — Milestone 1 ships the editor pane as a
   placeholder; the layout/persistence model must not bake in assumptions that the
   real editor (M2) would have to unwind.
