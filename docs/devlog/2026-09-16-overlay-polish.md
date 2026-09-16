# 2026-09-16 — New-session and overlay polish

A focused pass toward the precision and restraint of Raycast/Things, keeping
Atelier’s compact chooser and its Catppuccin/two-voice design.

## Changes

- Shared neutral floating material for the worktree chooser, command palette,
  file picker and repository search. Hairline enclosure, existing shadow/radius
  tokens, opaque fallback when Reduce Transparency is enabled.
- A labeled primary action: Start session, Choose, or Create & start, with a
  Return hint. Consistent hover/pressed/disabled feedback and larger close and
  remove hit targets, using the existing hover-pad idiom.
- Explicit current-worktree checkmark, independent of the navigated row.
  Long branch names truncate in the middle; full paths are available on hover.
- Bounded worktree scrolling with keyboard reveal, including wrap to New
  worktree. Hidden lists are actually hidden from accessibility, not merely
  transparent. Worktree choices and custom actions have accessibility labels.
- Empty/invalid branch names disable creation. A quiet inline message replaces
  an unexplained enabled action; typing an existing name still selects it.
  Local validation covers ref-name syntax; git remains authoritative for
  repository-specific conflicts.
- Cards adapt to available window width; list heights adapt to available
  height. Card width uses a constant updated on resize: a horizontal equality
  to the host caused AppKit to shrink the entire window to its fitting width.

## Validation

Production SwiftPM build and diff whitespace check. An isolated AppKit preview
uses the actual chooser/overlay/Summon sources and the same Theme values (only
terminal-only declarations and the Settings dependency are omitted). Its
fixture callbacks update a label; they never create/delete worktrees or start
agents. Original HEAD sources are included alongside the revised sources for
matched Before/After captures.

Visually exercised: collapsed/expanded chooser, long names, empty and invalid
names, valid confirmation, Escape through modes, 30 worktrees, arrow wrapping
and final-row reveal, palette results/no results, and window resizing. The
preview caught two scroll-reveal errors and an AppKit window-sizing trap,
which were corrected during the pass.

The existing live application and sessions were left running. Integration
with real worktree creation/removal was not exercised; those callbacks and
their confirmation paths are unchanged. Reduced-motion/transparency code paths
are preserved/implemented, but OS accessibility preferences were not changed
for this pass.
