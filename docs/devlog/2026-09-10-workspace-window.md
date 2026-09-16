# 2026-09-10 — The workspace window, the vendored terminal, the attention palette

The sequel to the 2026-09-03 entry. Corey lived in the folders build for a
week and the verdicts came in sittings: the folders should poke over the
content, not fatten the bar; tabs and folders should drag; the chooser
should show the worktrees it's choosing among; a repo with an underscore in
its name never got a title. Then, once the strip settled, the bigger one —
projects as tabs of *one* window, drawn by Atelier, because native window
tabbing put AppKit's chrome between the titlebar and ours. Underneath all
of it, Claude Code 2.1.26x had turned on mouse reporting and the agent pane
stopped scrolling; that fix took us into SwiftTerm itself.

## What changed

- **Folders, tints, the glyph.** The 09-03 entry's addenda carry the 09-07
  and 09-08 verdicts in detail (labels overhang the 30 pt bar, folders name
  the worktree, branch chip on hover, `main` for the primary, one group →
  bare tabs). The tint went three rounds after that: 42 % toward a hashed
  Mocha accent, then accents *assigned in key order* so no two open
  folders shared one (`5a06262`), then locked while open so a new folder
  never recolored a neighbor and sky gave way to yellow (`375c1b9`), and
  finally — the owner's 09-10 call — **no hue at all**: every worktree
  folder shares the main folder's surface0 and differs only in lightness,
  stepping outward as worktrees arrive (lighter, darker, lighter still,
  darker still; `Theme.Folder.body`, poles overlay0 and crust). Label coats
  pull one step toward mantle and go opaque so subtext0 holds on any rung.
  The main folder keeps its grouping but lost its label tab — it is the
  ground the others stand on (`aa864aa`). The worktree glyph converged the
  same way: the SF `tree` symbol, then a path traced from the owner's own
  silhouette, then a conifer — a canopy turned to a lollipop at 10 pt —
  whose trunk first ran up into the lowest tier to hide a seam, then had to
  *wind* with the tiers because an opposite-wound overlap cancels to a hole
  under the non-zero rule; three tiers collapsed into a blob so two; the
  top tier widened over the skirt; and on 09-15 the owner picked one of
  eight variants, a 10×12 stepped-side conifer drawn as one outline so the
  tier step is a hard horizontal edge that survives 2x
  (`BottomBar.treePath`).
- **Drag to arrange** (`811b906`). Tabs reorder within a folder past a
  sibling's midpoint; pushed into a neighbor folder, the folders swap. The
  label tab is the group handle with the open-hand cursor.
- **Chooser rebuilt** (`5a06262`, `WorktreeChooser.swift`). It suggests the
  worktree you're in and unfolds the full list inside the card — rows
  removable by a hover `×` behind the guarded modal's "anything not pushed
  is lost" warning — with typed text centered. Prunable worktrees
  (directory gone) are dropped; the primary is tagged "main checkout"
  whatever branch it has out (`030a95d`).
- **Session tab `×`.** Moved to the trailing edge and confirms via an alert
  with "Don't ask again" (Settings → Ask before closing a session,
  `ProjectController`). Then hugged the title's real end — 3 pt off the
  text, 4 pt off the edge, with measurement slack kept outside
  the button (`6822843`, `237ac56`).
- **The project tab row** (`5ca60ae`, `WorkspaceWindowController.swift`,
  `ProjectStrip.swift`). Projects are tabs of a single window.
  `WorkspaceWindowController` owns the window, the titlebar wash, and a
  full-width row under it: tabs divide the row equally, the selected one is
  a rounded chip, and every tab carries its sessions' attention marks after
  the title, so a project you aren't looking at still says where its
  agents stand. The row collapses with one project; `+` opens one; the
  active tab's `×` closes it (dirty-buffer refusal first; the last one
  closes the window and the app). `MainWindowController` became
  `ProjectController` — a view below the row, hidden while another project
  is up, sessions running throughout; focus requests from a hidden project
  are dropped, and coming on screen turns the active session's unseen
  completion into waiting exactly as focusing its tab does. Overlays mount
  on the project view. Restore lands on the tab active at quit. Menu: `⌥⌘W`
  Close Project, `⌃⇥`/`⌃⇧⇥` cycle; `⌘T`, `⌘1..9` as before.
  `window.tabbingMode = .disallowed` so AppKit stops injecting tab items.
  Two follow-ups the same day: Ghostty's read — the selected tab flush with
  the panes' base, the rest darker in crust, titles subtext0 with the
  selected one at full text via a new `Theme.chromeSelectedText` (the one
  current thing is the only chrome above the §1.2 cap); then `×` at the
  leading edge and a size up — 26 pt tabs in a 32 pt row, body-size titles.
  Window titles dropped ` — worktree` / ` — dir`: repo or host name only.
- **Attention survives relaunch** (`aa864aa`). `PersistedSession` carries
  the tab's attention; restore maps it to what a resumed, idle agent can
  honestly show — unseen completion stays, anything mid-flight or blocked
  comes back as plain waiting.
- **Tab titles for underscored repos** (`e59b379`, `aa7268e`). Claude Code
  encodes the transcript directory by replacing *every* non-alphanumeric
  character in the cwd with `-`; our reader swapped only `/` and `.`, so
  `BCI_HW1` never found its transcript and kept the folder name. Worse,
  `Session.transcriptExists` had its *own* encoding that preserved `_`, so
  a restored session concluded it had no transcript, spawned with
  `--session-id` on a known id, and Claude refused it: "Session ID already
  in use". Both now route through `TranscriptTitle.transcriptPath` (with a
  project-dir scan by session id as the fallback if the encoding drifts
  again), and restore resumes whenever a transcript exists.
- **The attention palette** (`8d6a22d`, `f4d0032`, `b569f0b`;
  `AttentionMarks.swift`). In the normal flow every session ends its turn,
  so every project went peach — trouble, when nothing was wrong (owner
  call 09-15). Now three colours, three meanings: blue busy, green your
  move (seen or not), peach the one blocked state. Unseen completion keeps
  its green and *pulses* clearly (~1.2 s, to 25 %) until you look; working
  keeps its subliminal pulse. `AttentionDotView` is shared by both tab rows
  and installs the motion once its layer joins a window; the strip rebuilds
  marks only on change so the pulse never restarts on a refresh. The `!`
  went twice: first cut into a peach disc as one drawn `BlockedMarkView` (a
  typed `!` beside dots read as a stray character), then, with one state
  per hue, dropped altogether — every mark is a plain dot.
- **Hover pads** (`6413e7c`, `HoverPadButton.swift`). One button replaces
  the bar's `HoverFadeButton` and the strip's `StripHoverButton`: the glyph
  rests dim and stays dim; hover paints a 16 pt rounded pad behind it —
  light on the project tabs, dark over the session tab's green. The macOS
  tab close's manner.
- **Dev seed** (`e1dbda0`). `make run-states` (or
  `ATELIER_DEBUG_ATTENTION=1`) gives the active project one session per
  state — working / waiting / blocked / unseen-done — adding Landings as
  needed without moving you off your tab; re-triggerable over the socket as
  the `seedAttention` debug message once real hook events overwrite it.

## Terminal

Claude Code 2.1.26x draws on the alternate screen with mouse reporting on
(`?1049 ?1000 ?1006 ?1007`). SwiftTerm scrolled its own empty scrollback for
every wheel event, so the transcript could not be scrolled at all. The fix
belonged in the terminal, as in Ghostty, not as another app-side override —
and SwiftTerm's AppKit view seals the methods it lives in (`public`, not
`open`). So **SwiftTerm 1.13.0 is vendored** at `Vendor/SwiftTerm`
(library target only, provenance and the patch list in `ATELIER.md`, each
meant for upstream):

1. **Wheel routing** — `Terminal` tracks DECSET 1007; `scrollWheel`
   branches three ways: mouse reporting on → button 64/65 reports at the
   hit cell; alternate screen + alternateScroll → ↑/↓; otherwise local
   scrollback. Verified byte-for-byte with `cat -v` under both modes.
2. **`open` hooks** — `scrollWheel`, `resetCursorRects`, `cursorUpdate`. The
   arrow-pointer patch became a plain override and the `addCursorRect`
   trick from 09-07 is gone; `cursorUpdate` needed it too, since SwiftTerm
   set the I-beam there directly, bypassing the rects.
3. **SGR motion** — Claude Code enables any-event tracking (`?1003`) to
   brighten clickable text under the pointer. SwiftTerm's encoder saw
   button code 3 on a motion report and emitted a *release*
   (`CSI <32;x;y m`), so every hover landed as a click and tool calls
   toggled open and shut as the pointer crossed them. Motion with no
   button is `CSI <35;x;y M`.
4. **`showsScroller`** — the legacy `NSScroller` never scrolled anything on
   the alternate screen and cost 15 pt of grid width. Off in Atelier.
5. **`wheelPrecisionMultiplier`** — quantisation now matches Ghostty's core
   exactly (accumulate pixels, one report per cell height, truncate the
   remainder, no per-event cap); the knob is Ghostty's
   `mouse-scroll-multiplier.precision`, set to 1.5 after an owner
   feel-check.
6. **`copyOnSelect`** and 7. **OSC 52 forwarding** — see below.

The **⌘-chords** are *not* in the vendored copy: `⌘⌫` kills the line,
`⌘←/→` Home/End, `⌘⇧←/→` select, `⌘↑/↓` → `⌃↑/↓` — byte-for-byte the
dotfiles' `ghostty/config` text bindings, handled in `performKeyEquivalent`
on the focused terminal view. A host keymap, as in Ghostty, not emulator
behaviour.

**Clipboard parity** (`0df28e6`). Owner report: highlight didn't copy, and
Claude Code's "c to copy" on a remote host said copied with nothing on the
pasteboard. Patch 6: a finished mouse selection (drag, double/triple click)
goes through `copy(_:)`, so the agent pane's transcript-aligned copy applies
too; empty selections leave the pasteboard alone. Patch 7: SwiftTerm parsed
OSC 52 and the local view knew how to write the pasteboard, but the
`TerminalDelegate.clipboardCopy` default sat empty between them — it now
forwards. Remote tmux conf v5: `set-clipboard on` plus an `Ms` terminfo
override for xterm-256color so tmux forwards the inner OSC 52 out to Atelier
(`Remote.swift`); every attach re-sources the conf so live servers pick it
up. Verified locally: drag and double-click copy, OSC 52 from the shell
lands.

## Gotchas

- **Drag hauled the window.** `isMovableByWindowBackground` plus non-opaque
  views answering yes to `mouseDownCanMoveWindow` — the bar, tabs, and
  folders now say no. The strip's own `hitTest` returns nil for its gaps so
  those *do* still drag and double-click-zoom the window.
- **Tracking areas on views that re-share a row.** Project tabs re-lay out
  on every add/close; AppKit only asks a view to `updateTrackingAreas` once
  it already has one. `HoverPadButton` and `ProjectTabView` install theirs
  at init with `.inVisibleRect` so the rect follows the frame.
- **Layer animations before the window.** `CAAnimation`s added to a layer
  that isn't yet in a window are dropped; `AttentionDotView` installs its
  pulse in `viewDidMoveToWindow`.
- **Non-zero winding.** The conifer's trunk had to run clockwise like the
  tiers; wound the other way, the overlap punched a hole at the join.
- **Two cwd encoders.** Any second copy of "how Claude names the transcript
  dir" will drift. There is one now.
- **Peach as the default.** A state colour that fires at the end of every
  turn is not an alert; it's wallpaper. The palette has to reserve its
  loudest hue for the state that is actually rare.

## Open

- Patches 1–7 are each meant as an upstream SwiftTerm PR; none is filed.
- The `forkpty` startup deadlock from the 09-08 addendum is still
  unmitigated.
- The conifer at 10×12 and the lightness rungs are owner eyeball calls;
  both were picked in situ and may move again.
