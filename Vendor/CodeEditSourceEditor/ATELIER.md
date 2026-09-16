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
