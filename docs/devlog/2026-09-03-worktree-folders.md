# 2026-09-03 — Worktree folders, the chooser, and Settings

Corey came back after six weeks with the first v1.0 verdicts. Opacity: right,
but it should be a slider. Worktrees: the pill fan goes; worktree choice
becomes part of starting a session; the tab strip should show worktrees as
physically separate folders. Then, mid-build: the modal must be *small* (×
top-left, a `↩` keycap bottom-right, caption over dropdown), gated behind a
settings toggle, and the bar needs a gear.

## What changed

- **`WorktreeFan.swift` deleted.** The pill is a static label now.
- **`WorktreeChooser.swift`** — the modal. `ChooserKeyView` hosts the pick
  mode's keyboard (↩ / Esc / ↓ space tab / printable → name mode); the name
  field is a plain `NSTextField` whose delegate claims *both*
  `cancelOperation:` and `complete:` — AppKit's field editor turns an
  unhandled Esc into the autocomplete popup, which is exactly what happened
  on the first driven run (the modal stayed up, focusless, and swallowed
  every later chord).
- **`BottomBar`** — `FolderView`: one `NSBezierPath` (tangent arcs) for cell
  + label tab so a half-alpha fill never doubles at the join; continuation
  segments (a group split across rows) draw a bare cell. The flow now packs
  *segments* with a reserve for the trailing buttons (second pass if `»` is
  needed — the old flow could squeeze the `+` off a full second row). Pill,
  clock, toggle, gear all sit on the bottom row's tab axis (`bottomRowAxis`),
  not the bar's center, since the label band lives above the tabs. Heights
  44/86.
- **`Theme.Folder.fill(i)`** — surface0, then surface0 blended 22 % toward
  blue/mauve/teal/peach/pink, all at 0.6 alpha.
- **`Settings.swift`** — `Settings.fieldAlpha` (UserDefaults, env override
  still wins) and `Settings.worktreesEnabled`; every field surface that
  already re-read tokens on Reduce Transparency now also observes
  `Settings.didChange`, so the slider is live. `Theme.fieldAlpha` is a
  computed passthrough. `SettingsWindowController.shared` on `⌘,` and the
  gear.
- **Controller** — `requestNewSession()` is the `+`/`⌥⌘T`/palette entry:
  remote → sibling; repo + worktrees enabled → chooser; else main. Folder
  labels come from `folderLabel(for:key:)`; the main branch is cached
  (`refreshMainBranch`) so the strip never shells out per redraw. Removal:
  `removeWorktree(atPath:)` from the folder's context menu and the palette;
  `removeWorktree(branch:)` from the CLI. The orphan-restore notice opens the
  chooser in name mode with the dead branch prefilled.

## Verified

Snapshot-driven (IPC `snapshot`, System Events keystrokes): four seeded
sessions across main + two real worktrees render as three folders; ⌥⌘T →
type → Esc (back to pick) → Esc (gone) → ⌥⌘T → ↩ lands a third tab in the
main folder; Settings opens from the menu with both controls at their stored
values.

## Left for the owner

Folder tint strength and the 44 pt bar height are eyeball calls. The
`worktrees.enabled` default was left **on** in the owner's defaults after the
test run (code default is off).

## 2026-09-07 addendum — the owner's first live pass

Five verdicts in one sitting, all landed:

- **Titlebar double-click didn't zoom.** With `titleVisibility = .hidden` the
  titlebar passes clicks to `TitlebarWashView`; it now re-speaks the system
  `AppleActionOnDoubleClick` (zoom default, minimize if set).
- **Folder labels poke over the content**, not into a taller bar: heights back
  to 30 / 72, cells stack from the bottom, the top row's label tabs overhang.
  Nothing clips — but AppKit rejects hits outside a view's frame, which made
  the overhanging label a 2 pt target. `BottomBar.hitTest` now gives the strip
  first refusal on any point and `TabsAreaView` tests children frame-free.
- **Drag to arrange.** Tabs reorder within a folder; folders swap when pushed
  past a neighbor; the label tab is a group handle with the open-hand cursor.
  First driven attempt hauled the whole *window*: `isMovableByWindowBackground`
  plus non-opaque views answering yes to `mouseDownCanMoveWindow`. The bar,
  tabs, and folders now say no. Swap threshold moved from center-crossing to
  leading-edge-past-midpoint (+6 pt) per the owner's feel. Folder tint is
  keyed to the worktree (hash), not strip position, so swaps don't recolor.
- **I-beam over terminals** → arrow. SwiftTerm's cursor methods aren't `open`;
  the subclass overrides `addCursorRect` and substitutes the arrow.
- **`make install`** symlinks the bundle into /Applications for Spotlight.
