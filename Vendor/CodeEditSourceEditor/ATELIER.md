# CodeEditSourceEditor — Atelier's vendored copy

Upstream: https://github.com/CodeEditApp/CodeEditSourceEditor at 0.15.2
(424453d2232c9912933a3b5a1f3d3df669404ed0), `.git` stripped. Referenced
as a local path package from the root manifest; its own dependencies still
resolve remotely, except CodeEditTextView and CodeEditSymbols, which the
root overrides by identity with `Vendor/` copies.

## Patches (each meant for upstream)

1. **Hidden minimap swallowed clicks** (`Minimap/MinimapView.swift`).
   `MinimapView.hitTest` returned `self` for any point in its visible rect
   without checking `isHidden`; as a floating subview of the scroll view
   it is still consulted while hidden, so with `showMinimap == false` the
   right ~17% of the editor could not be clicked. Now returns nil when hidden.

2. **Gutter insets 10/12 instead of 20/12** (`Gutter/GutterView.swift`).
   Taste, not a bug — Atelier's call; not for upstream. With the fold ribbon
   off (config) the gutter is ~47pt for files under 1000 lines.

3. **Find bar shows position** (`Find/PanelView/FindSearchField.swift`):
   "3/10" instead of "10 matches".
4. **VSCode chords** (`Controller/TextViewController+Lifecycle.swift`,
   `Controller/TextViewController+AtelierChords.swift`): ⌥⌘↑/↓ add caret
   above/below, ⇧⌥↑/↓ duplicate lines, ⌥↑/↓ move lines (upstream had the
   methods, no binding), ⌘D select next occurrence.
5. **Per-capture theme attributes** (`Theme/EditorTheme.swift`,
   `Enums/CaptureName.swift`): `EditorTheme.captures[CaptureName]` is
   consulted before the eight coarse slots, and `CaptureName` gains the
   captures the bundled queries already emit (function.builtin, constant,
   constant.builtin, operator, punctuation, escape, type.builtin,
   attribute, namespace, label) plus prefix fallback for dotted names.
   Before this, `def`, `self`, `None`, operators and builtin calls in
   Python all rendered as plain text.
6. **One capture per range** (`TreeSitter/TreeSitterClient+Highlight.swift`,
   `highlightsFromCursor`). When a generic capture (`(identifier)
   @variable`) preceded a specific one (`@function`) for the same node,
   both were emitted and the style container kept the first — function,
   method and builtin names rendered as variables in every language whose
   query has a catch-all identifier pattern. Now the lowest-indexed capture
   wins outright and results come back in document order.
7. **⌘F seeds from the selection** (`Find/FindViewController+Toggle.swift`):
   a non-empty single-line selection becomes the find text when the panel
   is summoned (and re-seeds when it's already up).
8. **Jump-to-definition reachable from AppKit** (`Controller/
   TextViewController.swift`, `JumpToDefinition/JumpToDefinitionModel.swift`):
   `jumpToDefinitionDelegate` + `linkHoverColor` public on the controller
   (upstream sets the delegate only through the SwiftUI wrapper). The hover
   now asks the delegate for links before showing the hand — an identifier
   with no definition keeps the arrow — caches them for the click, and
   underlines in the theme colour instead of a filled selection box.
9. **Editing chords fall through on a read-only view** (`Controller/
   TextViewController+Lifecycle.swift`): the local key monitor consumed tab,
   ⌘/, ⌘[ ⌘], ⌥↑↓ and ⇧⌥↑↓ even when `textView.isEditable` was false, and
   every one of them then hit the `isEditable` guard in `replaceCharacters`
   — a silently swallowed keystroke. `handleEvent` now returns the event
   untouched for a read-only view so it travels the responder chain; the
   host decides what typing into a read-only buffer means (Atelier: it
   enters the previewed file, then replays the key).
