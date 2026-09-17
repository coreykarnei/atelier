# 2026-09-17 — Post-release tweaks

The first day of driving 1.0, written up as it happened on
`feat/post-release-tweaks`. Owner reports came in one at a time; each was
reproduced in an isolated test instance beside the live app, fixed, and
committed on its own.

## The test harness

`ATELIER_STATE_DIR` relocates the socket and the session file, so a second
build runs beside the live app without touching its sessions. The explorer's
search field doubles as a probe channel (`explorerSearch` over the debug
socket): `probe:preview=`, `probe:enter=<gesture>`, `probe:key=`,
`probe:drag=`, `probe:click=`, `probe:move=`, `probe:explorer`, `probe:bar`,
`probe:hit`. Snapshots preserve alpha, so translucency is measured, not
eyeballed. Two things the harness cannot do: posted pointer moves never drive
tracking areas (warp the real pointer with the app frontmost), and layer masks
don't render in `cacheDisplay`.

## Changes

- **Editor wash.** The buffer compounded to ~0.94 alpha where the terminals
  sat at 0.75 — the pane painted a colour and the library's scroll view
  painted another over it. One wash now, alpha-probed at 0.749 everywhere.
- **Read-only preview.** `⌘X` in a click-preview cut text without entering
  the file. The preview buffer is `isEditable = false`; an editing keystroke
  enters first and then replays. Two vendored patches (CodeEditTextView #5,
  CodeEditSourceEditor #9) let a read-only view place its caret and pass keys.
- **Project row scrolls** past a 180pt tab floor instead of the `…` menu.
- **Worktree label survives** as the only group left.
- **Live divider resize.** The grid follows the pointer; the PTY hears one
  resize per 50ms beat. A `Timer` never fires inside `NSSplitView`'s tracking
  loop; a dispatch beat does.
- **Search panel.** Eager preview of the highlighted row, hover previews,
  centring measured after a forced layout pass, results held until the engine
  answers. The FSEvents `.git` filter compared `/tmp` against `/private/tmp`,
  so the explorer's own `git status` reloaded the tree in a loop and blanked
  the results each time.
- **Tab titles off the main thread.** `sample` put 40% of main-thread time in
  a 2s poll that re-read and JSON-parsed every transcript. Incremental reads
  on a utility queue; the judder is gone.
- **Resizable tree.** A 5pt grab strip on the hairline; one remembered width.
- **Per-folder `+`.** Owner design: a `+` per folder that means "a session
  here", one always visible in the active folder. The refinement that made it
  sit right: reserve the slot always, draw the glyph always at three volumes,
  hug the last tab by 2pt, pad the closed edge by 3, space folders 14 apart.
  The first cut floated a 10pt mark in the inter-folder gap and read as
  disabled; measured on the live strip, adjusted, re-shot.
- **Search marks.** Two bugs, found in sequence. `rg --column` is a byte
  column; the buffer read characters, so multi-byte glyphs ahead of a match
  pushed the mark right and often off the line. Then, with that fixed, marks
  on soft-wrapped rows past the first still vanished: `rectsFor(range:in:)`
  fed line-relative offsets to a fragment whose x-lookup is fragment-relative,
  so both bounds clamped to the fragment's right edge (CodeEditTextView #6,
  still present upstream at the time of writing).
