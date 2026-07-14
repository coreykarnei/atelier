# 2026-07-13 — Interaction pass

The polish pass (POLISH_PLAN) was pixel-level; this pass is interaction-level.
The owner's brief, distilled: the app's quality gap lives in the first
half-second after an intent — ⌘T should mean *a cursor already blinking over a
list that anticipates you* — and the docs carry requirements, not taste. The
confirmed bar: Raycast/Things-grade instrument feel. Every surface opens ready
to receive typing, the first keystroke always lands, focus is never ambiguous,
nothing promises an interaction it doesn't deliver.

## 1. The summon idiom (`Summon.swift`)

The command palette already had the right interaction — autofocused field,
live subsequence fuzzy filter, recents-first, sliding highlight — but all of
it was private to `CommandPalette.swift`, and the app's front door (the
Landing) had none of it. Extracted as **`SummonList`**: one shared
type-to-choose surface. Field on top (it owns keyboard focus for the surface's
whole life; the list refuses first-responder so typing never stops working),
divider, fuzzy-filtered list with the sliding highlight. Row 0 re-selects on
every keystroke so `↩` always has a target; arrows move (and scroll); a single
click activates; `Esc` optionally clears the query before escaping (Raycast
behavior — the Landing uses it, the palette keeps VSCode's immediate escape).
When nothing matches, the surface says so in one muted line — never the old
8 pt sliver.

The palette is now a thin host: floating card chrome + command semantics over
a `SummonList`. The M2 `⌘P` picker inherits the idiom whole.

## 2. The Landing, rebuilt (owner-directed posture)

`⌘T` now lands the cursor in a filter field on a **centered raised card** in
the upper-middle of the pane — the Raycast posture, per live owner direction:
card centered, field near vertical center, **terminal keeps the bottom third**
(`landingVertical` default fraction 0.32 → 0.67). Specifics:

- Card: `base` fill (so the `surface0` highlight reads against it, per the
  elevation ramp), `radiusLarge`, raised shadow, top hairline. Width 560 — the
  palette's card width; one summon silhouette everywhere.
- The card hugs its results (the palette's §6 height-tracking, embedded):
  grows as matches appear, shrinks as the query narrows. Capped at exactly
  12 rows so the cap never cuts a row mid-height.
- The offer re-scans on every show and window-key return — a repo cloned in
  another app appears, a deleted directory drops out — and `RecentsStore` now
  prunes dead paths instead of hiding them per-render. The live query *and the
  user's arrow selection* survive every refresh (selection preserved by id).
- Opening re-checks the directory at decision time; a dead entry re-scans
  instead of promoting to a corpse.
- Two-voice hint line under the card: `↩` open · `⌘↩` `ide` in terminal dir ·
  `⌃⌘j` shell — chords and the `ide` command in mono, prose in ui (§1.4). The
  hints are now *true*: `↩` genuinely opens, because focus is genuinely there.
- Placeholder "Open a project…" is Atelier speaking → ui voice; the typed
  query is a repo name → mono. (`SummonList.Style.placeholderFont`.)

**Focus flip (§2.1 revision):** the Landing was terminal-first [M1.2]; it is
now opener-first — `⌘T` means "open a project," so the first keystroke lands
in the filter. The shell stays one `⌃⌘j` away and the hint says so.
MILESTONE_1 §2.1 amended with the dated revision.

## 3. Review findings (multi-agent adversarial pass, all fixed pre-commit)

An adversarial review (3 lenses × verify agents, several claims reproduced in
live AppKit harnesses) confirmed and I fixed:

- `allowsEmptySelection` regression: an empty-strip click deselected while the
  highlight kept lying, making `↩` a silent no-op. Now `false` + a
  `clickedRow >= 0` guard so dead-space clicks can't activate rows either.
- Palette activation resolved commands by id — two project windows with the
  same title collide on `project.switch.<title>` and the wrong window won.
  Items are now position-keyed; recents still bump the stable command id.
- **Overlay dismissal restored focus to `defaultFocusView`** — on a landing
  that's now the filter field, so `Esc` after working in the landing shell
  dropped the next keystrokes into the filter, where `ls⏎` could fuzzy-match
  and *promote the session* (irreversible, spawns Claude). Overlays now
  capture the pre-overlay first responder and put it back.
- Refresh-on-key-return reset the arrow selection to row 0 (fixed by the
  preserve-by-id above); refilter selected row 0 without scrolling to it.

## Residual

- The summon field's caret is the system insertion point; the terminal panes'
  caret truth (Phase 1) doesn't extend to it. Watch on a live look.
- `SummonList` height-tracking is duplicated in its two hugging hosts
  (palette, landing) — unify if a third host wants it (⌘P will).
