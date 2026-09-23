# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

**v1.0.0 tagged 2026-09-16; v1.1.0 (the post-release tweaks below) 2026-09-17; v1.2.0 (the worktree door below) 2026-09-21. Milestones 0, 1 and 2 built (M1.1–M1.6,
M2.1–M2.6 landed); polish pass (docs/POLISH_PLAN.md) built through all
phases — 0 (foundation tokens), 1 (cockpit), 2 (distances), 3 (arrivals),
4 (overlay physiology).** Read `VISION.md` (the
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
visible, every mark a plain dot since 2026-09-15: blue working, green your
move — waiting, or an unseen completion that rings until you look — and
peach for the one blocked state (ringing too while unseen); fed by hooks carrying
`session_id`, banner clicks focus the exact session), **worktree folders** in
the tab strip (2026-09-03: each root's tabs sit in a folder-shaped cell whose
label tab names the worktree — `main` / `⎇ dir` / `@host` — stepped lighter/
darker per group off the main folder's colour; two-row group-aware wrap + `»` overflow, overflowed tabs keep their
⎇/attention marks in the menu, and the `»` wears the loudest overflowed
state), a **Settings window** (`⌘,` / the bar's gear: field-opacity slider
applied live via `Settings.didChange`, Enable worktrees), and inline tab rename (double-click edits the title in place — ↩
commits a hard override of the live Claude title, Esc cancels, empty reverts;
titles uncapped).

**2026-09-16 polish pass** (merged from the `codex-polish` branch): one
`OverlayMaterialView` (base wash + hairline over the blur, opaque under
Reduce Transparency) under the worktree chooser, palette, file picker and
repo search; the chooser grew a labelled primary action (Start session /
Choose / Create & start, with `↩`), local branch-name validation with an
inline peach hint, a current-worktree checkmark, and a bounded scroll list
that reveals the keyboard selection; the project row moves tabs past a
180pt floor into an `…` overflow menu (the active tab always stays
visible); Settings is grouped (Appearance / Editing / Sessions, opacity as
a percentage); project/session items live in the File menu and "Find in
Repo" reads "Find in Project"; bar and header buttons carry tooltips and
accessibility labels. The pass is written up in `docs/devlog/2026-09-16-overlay-polish.md`.

Milestone 2 (complete as of v1.0.0): **M2.1 landed 2026-07-13** — the editor pane hosts a
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
edge, with a search panel (magnifier / ⌘⇧E: Files + Text toggles, both on
by default — the ⌘P offer and the ⌘⇧F ripgrep engine in one list) in place
of the tree;
single click previews (soft-wrapped), double-click/`↩`/the first keystroke
commits — unwrap, fold the tree to a 26pt rail with a chevron; `⌘B`
toggles. The open file is watched on disk; a clean buffer reloads in place.
`Vendor/CodeEditSourceEditor` (0.15.2) and `Vendor/CodeEditTextView`
(0.12.1) are vendored like SwiftTerm — editor-side fixes go there, each
meant for upstream, listed in each copy's `ATELIER.md` (hidden minimap
swallowing clicks; widest-line width never escaping layout so nothing
scrolled horizontally; scroll-to-visible following the selection box
instead of the caret). Settings → Autosave (also File → Autosave) writes
0.8s after each edit and silences the dirty guard. **2026-09-16:**
`Vendor/CodeEditLanguages` (0.1.20) is the fourth override — its query
path doubled `Resources/` under `swift build`, so no grammar ever
highlighted before this; with that fixed the editor paints one Catppuccin
colour per tree-sitter capture (`EditorPane.captureAttributes`,
`Theme.Editor`), Python's keyword buckets are split in the vendored query,
⌘F seeds from the selection, a diagnostic strip shows the message under
the caret, the file header carries `< >` history (⌃⌘←/→), and the Python
server is launched with the repo's `.venv` (root, one level down, or the
main checkout's for a worktree) as `python.pythonPath` + an activated
PATH. ⌘-hover shows the hand + underline only on symbols the server can
resolve (the library's jump model, `EditorPane` as its delegate). Twelve
more grammar queries were rewritten to nvim-treesitter buckets by a
fan-out of agents (JS/TS, Go, Rust, Ruby, PHP, Java, C#, C/C++, Dart,
Elixir, OCaml, Markdown; then bash, json, yaml, toml, css, html,
dockerfile, go-mod) and gated with **`atelier-hlcheck`**
(`swift run atelier-hlcheck <file>`; `Scripts/hlcheck/README.md`), which
compiles a query against the bundled grammar and prints every span the
way the editor resolves it — run it before touching any `highlights.scm`;
the precedence trap (capture-name first mention, not pattern order) is
documented there. `Scripts/hlcheck/shadow.sh` runs the prebuilt harness
against another checkout's queries — the loop for parallel query work. The triptych's two dividers can be dragged together from
where they cross (`SplitCornerHandle` in `Layout.swift`).

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

**Post-release tweaks (2026-09-16, `feat/post-release-tweaks`):** the
editor is a single-wash field like the terminals — `EditorPane` paints no
pane colour; `contentWash` (crust while empty, base with a file) is the one
coat and the library's scroll view/gutter background is transparent
(alpha-probed at 0.749 everywhere, where the buffer used to compound to
~0.94). The click-preview is **read-only** (`isEditable = false`): scroll,
select, copy — never mutate. Entering the file happens by exactly these:
tree double-click/↩, double-click in the buffer, or an editing keystroke
into the buffer (typing, ⌫, ⌘X/⌘V, the line chords), which enters first
and then replays the key (`EditorPane.enterPreview`; two vendored patches
carry it — CodeEditTextView #5, CodeEditSourceEditor #9). The project row
no longer folds tabs into an `…` menu: tabs floor at 180pt and the row
scrolls sideways (swipe, or a plain wheel), the clipped edge fades, and
selecting a tab glides it into view. A worktree or remote folder always
wears its label tab, even as the only group left. Dev: `ATELIER_STATE_DIR`
relocates the socket + session file so a test build can run beside the
live app (unix socket paths cap at ~100 chars — keep it short), and
`explorerSearch` gained `probe:preview=`, `probe:enter=<gesture>`,
`probe:key=` and `probe:drag=`. **Divider drags resize live**: the terminal
grid follows the pointer and the PTY hears one resize per 50ms beat
(`FreezableTerminalView.resizeThrottled`; a dispatch beat, not a `Timer`,
because the split view's tracking mode never fires default-mode timers);
`resizeFrozen` remains the hard freeze layout rebuilds use. **Search panel**:
the highlighted row is what the buffer shows — eagerly when results land,
and following arrows and the pointer (`SummonList.onSelectionMove`, coalesced
120ms in the explorer); a revealed hit is centred by measuring the line after
a forced layout pass (wrapped previews estimate unlaid lines at one row) and
the hit mark is placed from that layout, twice (`EditorPane.reveal`); text
hits stay on screen until the engine answers, and the FSEvents `.git` filter
compares Foundation-resolved paths on both sides — before, `/private/tmp`
roots let the explorer's own `git status` reload the tree in a loop, and
every reload blanked the results (`ATELIER_FS_TRACE=1` logs the events). **The tree's edge drags** (`ExplorerResizeHandle`, a 5pt strip on the
hairline, ↔ cursor): the width is one preference for every pane
(`FileExplorerView.width`, 160–560, clamped so the buffer keeps a column),
remembered across launches; double-click the edge restores 220. **Each folder carries its own `+`** (2026-09-16, owner design): an 18pt
slot is reserved at every folder cell's trailing end, always, so hovering
never reflows the strip; the glyph is always drawn — a whisper at rest
(subtext0 at α 0.22, the luminance of overlay0 at 0.35), full subtext0 in
the active session's folder and in the folder under the pointer (cell,
label or any of its tabs — `FolderView.onHoverChange`, a second geometric
tracking area). It hugs the last tab by 2pt with a 3pt cell pad after it
(the ink lands ~7pt off the closed edge, a hair more than a tab's 6),
folders sit 14pt apart, and the 12pt glyph wears a 16pt pad — the
2026-09-17 feel-check found a 10pt mark floating in the inter-folder gap.
The active tab's close `×` likewise rests at α 0.35 and rises to 0.85 over
its tab, instead of hiding until hover. Clicking a folder's `+` asks for a session *there*:
the worktree chooser opens with that worktree preselected (New… stays one
step away from any folder), worktrees off starts straight on that root, a
remote folder gets another session on the host. The trailing `+` survives
only in bare-tabs mode (main alone, no folder chrome); ⌥⌘T is unchanged
(sibling of the active session). Dev probes: `probe:bar` dumps the tab
area, `probe:move=x,y` posts a pointer move — note posted moves do **not**
drive tracking areas; to exercise hover, warp the real pointer
(`CGWarpMouseCursorPosition` + a posted `CGEvent`, as the 2026-09-17
feel-check did) with the app frontmost (`.activeInKeyWindow`). **Search
hits mark the right characters** (2026-09-17, owner report: many text hits
showed no highlight): `rg --column` and `git grep --column` both report a
1-based *byte* column, and the buffer read it as characters, so every `—`,
`⌘` or `⌃` ahead of the match on its line pushed the mark two places
right — often clean off the line, where it clamped onto the newline and
drew nothing. `SearchHit.byteColumn` is converted against the line's own
UTF-8 in `EditorPane.reveal(hit:)`. The second half was the library:
`rectsFor(range:in:)` fed *line*-relative offsets to a fragment whose
x-lookup is fragment-relative, so on any soft-wrapped row after the first
the mark collapsed to a sliver at the wrap point — every find/search mark
on a wrapped preview past row one (CodeEditTextView patch #6). `probe:hit`
reads the placed mark's range, text, layout rects and layer frames back.
**Explorer scans are single-flight and bounded** (2026-09-18,
`fix/explorer-reload-storm`, owner report: keyboard dead, pointer fine,
then a dozen "access data from other apps" prompts on quit): a session
promoted on `~` itself (home is a git repo) had the explorer reloading off
every FSEvents batch under the whole home directory, each reload spawning
another `git ls-files` + `git status --ignored` over all of it — sixty-odd
git processes in flight, the main thread freeing the last
multi-hundred-thousand-row offer while the next landed, and every walk of
`~/Library/Containers` billed to Atelier as a TCC prompt. Now
`FileExplorerView` runs one scan of each kind at a time with a dirty flag
(a reload during a scan re-runs it once), `RepoFileOffer.gather` always
completes and caps the offer at 20k rows with an honest tail row, the
superseded offer is released off-main, both scans take `-- .` so a
sub-folder root walks only its own subtree (porcelain paths are
repo-root-relative — they're rebased through `git rev-parse
--show-toplevel`, which also fixes ignore dimming for sub-folder roots),
and `RepoFileOffer.isUnboundedRoot` (`~` or `/`) skips both scans:
recents only, no dimming.

**A project wears the name of the folder you opened** (2026-09-21,
`fix/project-name-is-the-folder`, owner call): `ProjectController` split
the one anchor in two. `projectRoot` is that folder — the tab title, the
bar pill, and where `⌥⌘T` starts a sibling — while `projectRepoRoot` is
the primary checkout behind it and is now **nil when there is no repo**
(the old `?? cwd` fallback made it never-nil, so `repoRoot != nil` was
false comfort). Before, the title came from git's root, so opening a
subdirectory named the repo instead of the directory, and — because home
is itself a repo — a folder like `~/Ableton Projects` resolved all the
way up and titled its tab `core`, with the worktree chooser aimed at the
whole home directory. Dropping the fallback is what makes the three
worktree gates (folder `+`, `⌥⌘T`, the palette's Worktree: New…) mean
what they always claimed; `folderLabel` stops calling a repo-less folder
`main`, and the `atelier` CLI matches a window by
`projectRepoRoot ?? projectRoot`. The `.git` filter on the ⌘T Landing
offer (`LandingView.entries`) is untouched and still decides what the
scan *lists* — a plain folder is reachable by typing its `~`/`/` path.

**The `+` never asks; the `⎇+` is the door (2026-09-21, v1.2.0, owner
call).** Every `+` — bare, per-folder, `⌥⌘T` — starts a session
immediately, in the worktree pointed at or the active session's, with
worktrees on or off; the chooser no longer stands in front of them. It
is raised instead by a second glyph beside the `+`: the `⎇+`
(`BottomBar.worktreeAddGlyph` — `FolderView.treePath`'s conifer with a
plus laid over its right edge, knocked out by a clear halo), gated on
`Settings.worktreesEnabled && projectRepoRoot != nil` and re-read on
`Settings.didChange`, with `⇧⌥⌘T`, a File-menu item and a palette
command as its twins. It stands `worktreeAddStandoff` (8pt) clear of the
last folder cell — it is the row's control, not any folder's — and in
bare mode follows the `+` at the ink spacing the rest of the run keeps.
The card it raises opens *naming* a new worktree with the existing ones
listed beneath (primary last, `main checkout` + its drifting branch in
dim mono): type and `↩` creates, `↩` on an empty field starts the lit
row, a click starts that row outright, typing puts the highlight out,
hover and arrows share it. The strip also gained `TabRuleView`
hairlines between sessions of one group, before the group's `+`, and —
bare tabs only, where no cell edge does the work — between the `+` and
the `⎇+` (placed without the arrival fade, so they are right before the
selection colour moves), one volume for every `+` (the 2026-09-17
whisper is retired), and a brighter `HoverPadButton` pad (16% white,
26% pressed). Measured, not eyeballed: the card had sat 40pt
*below* centre (a positive `centerY` constant moves it down here), and
the trailing tick is seated off the title's ink, not the chip's frame.
Probes: `probe:worktreeAdd`, `probe:overlay`, `probe:key=down|up|tab|space`.
See `docs/devlog/2026-09-21-worktree-door.md`.

**The close button is Quit** (2026-09-23, owner report: a relaunch lost
every session). The red button used to tear every project down and then
quit with nothing left to snapshot — the unified log caught it: a click,
`finishing close`, then `applicationShouldTerminate` over an empty
workspace, and the next launch opened a blank Landing and saved *that*.
`WorkspaceWindowController.windowShouldClose` now routes to
`NSApp.terminate`, so the button is ⌘Q exactly (dirty guard, snapshot,
remote work left running). Ending sessions stays per-tab; the last
project closing by hand still closes the window through `close()`, which
never asks, and leaves an empty snapshot on purpose.

**Unseen marks ring; project-tab dots are doors** (2026-09-23, owner
call). A completion *or a block* that lands while you're elsewhere
(`doneUnseen`, and the new `needsInputUnseen`) keeps a steady dot and gives
off a hairline ring in its colour — bounds animated, not scale, so the
stroke stays 1pt; 2.2× reach, 1.3s travel on a 2s beat, phase-locked to one
app-wide clock so a row of them rings as one signal. Seeing the session
settles it (`Attention.seen`: green → waiting, peach → still blocked — a
seen block still never moves). Reduce Motion holds the ring still, halfway
out. The project tab's dots grew to 7pt and each is a `MarkButton`: pointing
hand, the hover pad's fills on a circle, press-and-release inside shows that
session (`ProjectController.focusSession(id:)` switches the tab *before* the
project comes forward, so arriving marks the right session seen); tooltip
`title — waiting · 4m` via the shared `AttentionTip`.

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
