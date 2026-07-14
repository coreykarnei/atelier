# 2026-07-14 — The content type scale: ⌘+/⌘−/⌘0, and Ghostty font parity

The owner, comparing the two IDEs side by side: "there's something about the
old one that somehow feels different… I think this one might just be a touch
bigger and feels more readable because of it. Maybe we just have to adjust
globally if we can't do scaling across all windows with cmd +-."

Diagnosis: Atelier's terminals were running **SwiftTerm's default font** —
the system mono at 13 — while the reference (dotfiles Ghostty) runs
**JetBrains Mono 14** with `adjust-cell-height 20%` and `font-thicken`.
Different face, smaller size, tighter leading: exactly the kind of
subliminal density difference that reads as "can't put my finger on it."

## What landed

- **`Theme.TypeScale`** — the one *content* type size. Terminals and the
  editor, every window at once; chrome (bars, tabs, overlays) keeps its own
  voice sizes and never scales. Defaults to Ghostty's `font-size` (14),
  clamps 9–24, persists (`type.scale`), broadcasts on change.
- **Terminals** now run JetBrains Mono at the scale — the same face the
  editor and the reference terminal use. Setting SwiftTerm's font re-runs
  its `setupOptions`, which re-copies the wash into the layer, so
  `applyTheme` (single-wash rule) and `positionWash` follow every change.
- **Editor** rebuilds its `SourceEditorConfiguration` on the same
  notification — `TextViewController.configuration` is a public var, no
  teardown needed.
- **Chords**: View → Bigger Text ⌘+ (with a hidden live ⌘= twin so the
  chord works unshifted), Smaller Text ⌘−, Reset Text Size ⌘0 — global
  actions on AppDelegate (no window target; the token broadcast reaches
  every pane in every window). Palette: `View: Bigger/Smaller/Reset Text`.

Verified live: menu-driven bumps re-rendered the running terminal at
16pt without restart (System Events menu click → snapshot), persisted
value read back 16, then reset to 14 for the owner's launch.

## The remaining Ghostty delta

SwiftTerm exposes no line-spacing knob, so Ghostty's
`adjust-cell-height = 20%` (airier leading) and `font-thicken` have no
equivalent yet. If 14pt JetBrains Mono still reads denser than Ghostty
side by side, that extra 20% cell height is the difference — closing it
means vendoring a small SwiftTerm patch (a `CellDimension` multiplier).
Owner's call after the live look.
