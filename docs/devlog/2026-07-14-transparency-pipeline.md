# 2026-07-14 — The transparency pipeline: it was arithmetic, not flags

## The bug

Two fixes in (window `isOpaque = false` + `.clear` backing; then
`.sidebar → .hudWindow` + `.active`), the owner still read the window as
fully opaque. Both fixes were real and both were insufficient, because the
bug was never a flag — it was compositing arithmetic:

1. **Terminals painted the wash twice.** SwiftTerm fills every cell's
   background (default cells use `nativeBackgroundColor`), and the view's
   layer *also* carried the wash. Two 0.85 layers compound to
   `1 − 0.15² ≈ 0.98` — a terminal that is 98% opaque.
2. **Everything sat on an NSVisualEffectView material.** Every AppKit
   material carries its own near-opaque tint; even `.hudWindow` under
   0.85 fields nets out around ~95%. Material choice tunes the tint, it
   cannot remove it.
3. The owner's reference — the thing the window sat next to and lost —
   is Ghostty at `background-opacity 0.75` / `background-blur-radius 20`,
   which uses **no material at all**: a flat alpha wash over the
   WindowServer's behind-window blur.

Net: ~95–98% opacity everywhere. "Fully opaque at a glance" was the
correct reading of a window on which every layer was working as coded.

## The fix — Ghostty's pipeline

- **`WindowBlur.swift`** (new): `CGSSetWindowBackgroundBlurRadius` via
  dlsym — the same private-but-long-stable call Ghostty and Alacritty
  ship. The window's content view is now a bare clear container; if the
  CGS symbols ever vanish, the old `.hudWindow` effect view is inserted
  as a logged fallback rather than shipping a raw see-through window.
- **`Theme.fieldAlpha` 0.85 → 0.75** — the owner's own tuned Ghostty
  value, and under this pipeline it is the *net* opacity, not an input to
  material stacking. One honest knob. `ATELIER_FIELD_ALPHA` (dev-only env
  var, read at launch) overrides it for live bisecting without rebuilds.
- **`Theme.backgroundBlurRadius = 20`** — Ghostty's radius.
- **Terminals paint the wash exactly once**: the SwiftTerm view's layer is
  cleared (cell fills carry the alpha'd background), the layer is clipped
  to the cell grid, and a `sliverWash` strip behind the terminal covers the
  sub-cell remainder at the bottom. The clip is what makes single-paint
  *by construction*: SwiftTerm sometimes paints that strip itself (partial
  scrollback row, normal buffer) and sometimes cannot (alt-screen TUIs —
  Claude, hx — have no scrollback), so without the clip the strip either
  doubled to 0.94 or dropped to raw blur depending on buffer state. The
  wash geometry is frame-set, recomputed from every authority that can
  move it (pane resize, layout, SwiftTerm `sizeChanged`) — the first
  constraint-based version went stale because the splits position panes
  imperatively.

## Verification — snapshots *can* prove the wash

The behind-window blur is composited by the WindowServer and never appears
in self-capture; only the owner can judge it. But the wash math is fully
measurable: `cacheDisplay` preserves the alpha channel, so a pixel probe
of the snapshot PNGs is ground truth for compositing. The snapshot debug
now also writes `state.txt` (live wash geometry + every translucent-
painting view with frame and color) next to the PNGs.

Before: terminal regions read `~250/255` (0.98). After: **191/255 = 0.749
uniformly across the window** — fields at exactly `fieldAlpha`, raised
surfaces deliberately denser, glyphs opaque, no seams at the grid
remainder. The alpha probes live in the session scratchpad
(`alphaprobe.swift`, `bandprobe.swift`, `rgbprobe.swift`).

Awaiting the owner's live verdict on the blur itself.
