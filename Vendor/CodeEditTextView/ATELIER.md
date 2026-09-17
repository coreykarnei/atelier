# CodeEditTextView — Atelier's vendored copy

Upstream: https://github.com/CodeEditApp/CodeEditTextView at 0.12.1
(d7ac3f11f22ec2e820187acce8f3a3fb7aa8ddec), `.git` stripped. Pulled in as a
local override by package identity, the same way `Vendor/CodeEditSymbols` is.

## Patches (each meant for upstream)

1. **Widest-line measurement never escaped `layoutLine`**
   (`TextLayoutManager/TextLayoutManager+Layout.swift`). `layoutLine` took
   `maxFoundLineWidth` as `inout` and then declared `var maxFoundLineWidth =
   maxFoundLineWidth`, so every update landed on the local copy.
   `maxLineWidth` stayed 0, `estimatedWidth()` was just the insets, and with
   `wrapLines == false` the text view's frame never grew past the viewport —
   long lines ran off the right edge with nothing to scroll into. Deleting
   the shadowing line is the whole fix. Still present on upstream `main` as
   of 2026-09-15.

2. **Scroll-to-visible followed the selection's box, not the caret**
   (`TextView/TextView+ScrollToVisible.swift`,
   `TextView/TextView+ReplaceCharacters.swift`). With wrapping off, a
   multi-line selection's fill rects run to `maxLineWidth`, so its bounding
   box is document-wide; `scrollToVisible` on a rect wider than the clip
   snaps to x = 0. Typing over a selection far to the right therefore
   yanked the viewport to the left margin. Both sites now use a new
   `caretRect(for:padded:)`: visibility is tested with the bare caret rect
   (an on-screen caret never moves the view); the reveal uses the padded
   one — a quarter of the viewport sideways (24…160pt), one line up and
   down — so a caret that was off screen lands with room around it rather
   than flush against the edge, the VSCode/Sublime manner.

3. **⌥-click adds a caret** (`TextView/TextView+Mouse.swift`). Upstream
   binds add-caret to ⌃⇧-click only; ⌥-click now does the same (VSCode).
   (A ⌘-click hook lived here briefly; ⌘-click is CodeEditSourceEditor's
   jump-to-definition model now — see that package's patch 8.)

4. **Recycled fragment views are detached, not hidden**
   (`Utils/ViewReuseQueue.swift`). `enqueueView` set `isHidden = true` on a
   subview of the first-responder text view; when that ran inside a key
   event (⇧⌥↓ → layout), AppKit's `_setHidden:` moved first responder to
   the window, so the following ⌘Z had no target. Layout re-adds every
   fragment view it lays out, so `removeFromSuperviewWithoutNeedingDisplay`
   is equivalent and side-effect free. Also adds `TextView.debugTrace` /
   `TextViewController.debugTrace` dev hooks (nil in production).

5. **Selectable views place the caret on click** (`TextView/TextView+Mouse.swift`).
   `handleSingleClick` returned to `super` whenever `isEditable` was false,
   so a selectable-but-read-only view had no insertion point: shift-click
   had nothing to extend, and a host that flips the view editable on the
   first keystroke had nowhere to put the text. `mouseDown` already gates on
   `isSelectable`; the click now sets the selection anchor the way NSTextView
   does for selectable text. Atelier's click-preview buffer is read-only
   until you enter it, and this is what lets "type here" mean here.

6. **Rects on wrapped rows use fragment-relative offsets**
   (`TextLayoutManager/TextLayoutManager+Public.swift`, `rectsFor(range:in:)`).
   The per-fragment loop passed the *line*-relative intersection to
   `characterRect(in:for:)`, but `LineFragment._xPos(for:)` walks the
   fragment's contents from zero (as `rectForOffset` already assumes, by
   subtracting the fragment's location). On any soft-wrapped row after the
   first, both bounds overflowed the fragment and clamped to its right edge,
   so `rectsFor`, `roundedPathForRange` and everything built on them — the
   emphasis manager's find/search marks, the jump-to-definition cursor
   rects, accessibility frames — drew a sliver at the wrap point instead of
   the text. Atelier's search-hit mark on a wrapped preview was the report
   (2026-09-17): matches past the first visual row never appeared.
