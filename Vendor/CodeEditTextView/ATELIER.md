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
