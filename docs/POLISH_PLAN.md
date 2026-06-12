# Atelier — Polish Plan: the beauty pass

The design companion to [MILESTONE_1.md](MILESTONE_1.md) for the refinement pass
that follows it. [VISION.md](../VISION.md) remains the authoritative *what*;
this document is the resolved plan for making the built workspace *beautiful* —
Apple-level polish and simplicity: not flashy, clean, tasteful, responsive.

**Provenance (2026-06-10):** an ideation pass over the built surfaces, a second
pass expanding it into system-level design (attention-at-distance, light, type,
sound, time), and a blind critique that evaluated both anonymously and
synthesized this plan. Two items were added by the owner afterward (marked
**[OWNER]**): the semitransparent background, and unifying the titlebar/project
tab strip with the app's material language. The critique's one-line verdict,
kept as the plan's compass:

> *Build the system the user lives in at every distance, and light it with
> pixel-level craft — and let the transition set-pieces go.*

**Status: Phases 0 (Foundations) and 1 (Cockpit) built (2026-06-11); Phases
2–4 not started.** Phases are dependency-ordered; each is independently
shippable. Nothing here blocks Milestone 2 — Phase 0 actively accelerates it.

---

## 1. The written rules

These cost zero code and protect every future surface (especially the M2
editor). They have the same standing as the keymap.

### 1.1 The steady-state motion inventory

The complete list of things permitted to move while nothing is happening:

1. Terminal content the user or agent is producing.
2. The focused pane's cursor.
3. The clock colon's sine breath (~1 Hz opacity ease — a breath, not a blink).
4. The working-blue dot's subliminal pulse (~4 s period, ±10% opacity).

That is the whole inventory. Everything else moves only in response to an
event, completes in ≤350 ms, and is then *still*. This forbids ambient shimmer,
perpetual spinners, and marquee-ing titles, forever.

### 1.2 Contrast discipline (four-hour eyes)

Terminal content runs at full Catppuccin contrast (text `#CDD6F4` on base).
Chrome never exceeds subtext (`#A6ADC8`) except the four attention accents.
Nothing in the app is ever pure white. (Implies a small real migration:
`Theme.chromeText` is currently full `text`.)

### 1.3 No escalation

A waiting session never pulses harder, never re-notifies, never changes color
with age. The truth is always available at every distance and it never raises
its voice. Time is available **on inquiry** (hover), never pushed.

### 1.4 The two-voice type rule

> If a string could be pasted into a terminal and mean something, it is mono.
> When Atelier itself speaks, it speaks SF Pro.

Mono (JetBrains Mono): paths, branches, commands, keycap contents, git-status
lines, session titles (the tmux-status idiom — a written-down exception),
clock, `line:col`. SF Pro Text: sentence-shaped chrome — modal explanations,
Landing hints, palette command names, the orphan-restore notice. The signature
move is the mixed line: an SF Pro sentence with a mono branch name inset.

### 1.5 The latency budget

Polish is mostly responsiveness. Standing policy: overlays are pre-built and
shown next frame; transcript/title I/O never rides the keystroke path; PTY
resize is debounced to drag-end; **Reduce Motion** gets cross-fade fallbacks on
every animation; **Reduce Transparency** gets opaque fills (see §2.1).

---

## 2. Phase 0 — Foundations (~1–2 days)

Tokens first: everything later reads from them, and the M2 editor is *born*
matching instead of retrofitted.

- **`Theme.Elevation`** — elevation *is* the Catppuccin layer. The Mocha
  neutral ramp maps one-to-one onto a z-axis: `crust` recessed wells (empty
  results panel, editor placeholder field) · `mantle` bars and frames (the
  bottom bar already — correct by instinct) · `base` content (terminals) ·
  `surface0` raised controls (active tab) · `surface1+` floating surfaces
  (fan, palette) over stronger blur.
- **The lighting model** — light comes from above: every floating surface gets
  a 1 px top hairline at ~6% white and one shadow token (y 8, blur 24, ~35%
  black); modals get a dimmed scrim. **Two shadows total in the entire app.**
  Corner radii from a three-value scale.
- **`Theme.Type`** — the §1.4 system codified: three sizes (11/13/15 pt),
  **tabular numerals always** for anything with digits, one keycap-chip style
  (mono glyph, `surface0` fill, 4 pt radius, hairline top edge).
- **§2.1 The semitransparent background [OWNER].** The blur substrate exists
  (`NSVisualEffectView`, behind-window) but every pane paints opaque base over
  it — the transparency the vision requires ("Catppuccin Mocha, transparent,
  native blur") is currently invisible behind content. Fix: one **translucency
  token** in `Theme` (base at a tuned alpha, ~0.80–0.90, over blur) applied to
  the terminal background (`nativeBackgroundColor` with alpha; the terminal
  view and window made non-opaque) and to the mantle surfaces (bottom bar,
  editor placeholder). Translucency applies to *fields, never text* — glyphs
  stay full-contrast per §1.2. Honor **Reduce Transparency** by collapsing the
  token to opaque. Tune the alpha against a busy desktop: the test is "depth
  without noise" — if wallpaper detail competes with text, raise it.
- **Write §1 into this doc's companion rules** and link from CLAUDE.md.

**As built (2026-06-10):** all of the above landed in `Theme.swift` —
`Theme.Elevation` (the z-ramp, `frameLine`, the hairline/scrim/two-shadow
lighting model, the 4/6/10 radius scale) and the type system as
**`Theme.Typography`** (Swift reserves `Type` as a member name), with
`mono()`/`ui()` voices, the 11/13/15 scale, and the keycap style (applied to
overlays in Phase 4). The translucency token is **`Theme.fieldAlpha`** — the
one constant to tune — collapsed to opaque under Reduce Transparency via
`effectiveFieldAlpha`, read at apply-time with a workspace-notification
re-apply in every field surface. Terminals paint translucent base
(`nativeBackgroundColor` + the SwiftTerm layer set directly); bottom bar and
Landing sit on translucent mantle; the editor placeholder is a translucent
crust well. Chrome text is capped at subtext0 (§1.2 migration done). One known
seam: SwiftTerm fills the sub-cell-height gap at a pane's bottom edge with
`nativeBackgroundColor` *over* the same layer color, so that strip composites
slightly more opaque (~0.98 vs 0.85) — invisible in practice; revisit only if
it ever reads as a band.

## 3. Phase 1 — The cockpit (~2–3 days)

The in-window hours dwarf everything else; this phase is exposure-weighted
highest.

- **Focus articulation** (thesis-level — "which pane has focus" is a literal
  sentence in VISION's definition of done): focused pane solid block cursor,
  unfocused hollow; a 1 px accent hairline along the focused pane's divider
  edge; a ~150 ms glow-then-settle when focus jumps via `⌃⌘+hjkl`. **Never dim
  unfocused panes** — you type in the shell while watching the agent stream.
- **The window as an object** — design the non-key state: hairline drops,
  cursors hollow, the `NSVisualEffectView` inactive desaturation embraced (the
  window "exhales" when you leave, sharpens on return). Terminal content does
  **not** dim — a background window with a streaming agent is something you
  intentionally watch.
- **§3.1 Titlebar / project tab strip unification [OWNER].** The native tab
  strip is currently stock AppKit material — visually a different app from the
  mantle-toned bottom bar. Target: **one material language from the top edge
  to the bottom bar** (mantle-over-blur tone, Mocha throughout). Approach
  ladder, cheapest first: (a) tune what the existing
  `titlebarAppearsTransparent` + dark appearance + full-size blur already give
  — the tab bar may only need the window's backing tint corrected; (b) tint
  via the titlebar's background (window `backgroundColor` /
  `NSTitlebarAccessoryViewController`) so the native tab bar sits on mantle
  like everything else. Constraint: **project tabs stay native window tabs**
  (MILESTONE_1 §2 is locked — the OS owns the strip's behavior; we restyle its
  setting, we don't rebuild the control). Acceptance: a full-window screenshot
  reads as one hand, one material. If AppKit's tab bar proves untintable
  beyond (b), document the residual gap here rather than forking into a custom
  strip.
- **The bottom-bar micro-pass**: one baseline grid (pill, tabs, clock, toggle
  on one cap-height — audit at 4×); tabular clock with the sine colon;
  attention-dot **cross-fades** (~250 ms) instead of swaps; green arrival does
  one soft scale-in (1.0 → 1.3 → 1.0) then stillness; the working-blue ~4 s
  pulse; the peach `!` **never animates** — urgency reads as stillness;
  **animated tab-width changes** so neighbors glide when Claude rewrites a
  title (retires MILESTONE_1 §12 risk #2, uncapped-title twitchiness).
- **The latency budget (§1.5) enforced** across existing surfaces.

**As built (2026-06-11):** focus articulation — lavender `Theme.Focus`
hairline constraint-pinned to the focused pane's divider edges (rides drags
free), 150 ms glow-then-settle on `⌃⌘hjkl`, solid/hollow carets synced to
window key status (SwiftTerm doesn't watch the window itself); first-responder
changes tracked via an `AtelierWindow.makeFirstResponder` override (NSWindow's
`firstResponder` KVO proved unreliable). Non-key: hairline drops, carets
hollow, `NSVisualEffectView` on `.followsWindowActiveState`. §3.1 landed as
rung (b)+: window backing tinted mantle, `titlebarSeparatorStyle = .none`, and
a mantle-over-blur **wash view** under the titlebar/tab-strip region — the
strip now shares the app's material; residual gap: the native tabs' own
selected/unselected fills remain stock dark-aqua (acceptable; the OS owns the
control). Bottom bar rebuilt on persistent per-session tab views with manual
flow layout: width changes glide (~200 ms), attention badges cross-fade
(250 ms), green arrival scale-in, working pulse (2 s out, 2 s back), peach `!`
inert, colon breath via a label subclass that (re)installs its animation in
`viewDidMoveToWindow` (AppKit drops animations added before the layer joins a
tree). PTY resize debounced to drag-end by bracketing NSSplitView's
synchronous drag loop (`LayoutSplitView.mouseDown`) and freezing terminal
`setFrameSize` for the duration. Reduce Motion is honored at every animation
site. One AppKit lesson recorded: never close a required horizontal equality
chain across the bar — AppKit then "resolves" the window's width from
constraints (it collapsed the window to 10 pt); keep one link an inequality
with a low-priority stretch.

## 4. Phase 2 — The distances (~1–2 days)

The attention model (§7.1) is the app's most original design; this phase
carries its four states, unchanged, to every distance inhabited during four
supervisory hours. Cheap rungs only — the expensive rung (peek card) is
deferred (§7).

- **The app icon, first** — the badge needs a worthy anchor. The triptych as
  the mark: three rounded panes in canonical proportions, base-on-crust, one
  pane carrying the lavender accent; flat, geometric. **Timeboxed to one day
  or commissioned.**
- **Dock badge** — `NSDockTile.badgeLabel` = count of sessions in **green or
  peach-`!`** state across all windows ("your move is the bottleneck" states
  only; not blue, not plain peach). Zero → no badge. An afternoon; the highest
  leverage/effort item in the plan.
- **Window titles** — `repo — branch`, so Mission Control thumbnails are
  legible at a glance. One line.
- **Elapsed time on hover** — hovering any attention dot shows one muted line
  (`working · 4m` / `waiting · 12m`) from the state machine's existing
  timestamps. Answers the one question dots can't, with zero always-on pixels.
- **No-escalation (§1.3) written into the attention-state code** as a comment
  with rule standing.

## 5. Phase 3 — Arrivals (~1–2 days)

The restore story is engineering-complete and experientially undesigned; the
morning open is the first impression of every single day.

- **The resuming placard** — kill the morning dead-terminal flash: until the
  first PTY byte, a restoring agent pane shows base material with two muted
  centered lines (session title in mono, `resuming…` in SF Pro),
  cross-fading out on first paint. No spinner (§1.1).
- **Restore stagger** — windows restore instantly; session tabs fade-and-settle
  left-to-right with ~40 ms stagger, sub-300 ms total. Once per launch, never
  again.
- **Permission on first promote** — the notification-permission prompt fires
  the moment the first agent exists (promote), not at launch. One-line
  reordering; the most Apple-feeling thirty seconds in the plan.
- **Refusals as designed objects** — the dirty-delete modal shows the actual
  `git status --short` lines in mono; the orphan-restore notice is an SF Pro
  sentence with the dead worktree names in mono and one button opening the fan
  pre-filtered to recreate. Same material for both.
- **Empty states** — the editor placeholder gets one centered hint line in the
  subtlest tone (not a gray rect); first-launch empty recents gets one
  designed line ("Nothing yet — `cd` into a repo and `⌘↩`", two-voice).
- **Quit stays instant** — `⌘Q` is the snapshot point; no exit choreography.

## 6. Phase 4 — Overlay physiology (~1–2 days)

Built last because this component *is* the future `⌘P` picker — the bridge
into Milestone 2.

- Fan rises from the pill with visible origin (scale from 0.96 anchored at the
  pill); palette descends mirrored from the top. **No row stagger** — at
  fan scale it reads as lag, not liquid.
- **Panel height animates to fit results** as you type (the Spotlight move —
  the single biggest "native" tell).
- Selection is **one sliding rounded-rect highlight** that glides between
  rows, not discrete repaints.
- Chords as keycap chips per `Theme.Type`, obeying the lighting model.
- Both overlays pre-built and shown next frame (§1.5).

---

## 7. Deferred (with conditions)

- **The session peek card** (last assistant paragraph on a session tab) —
  deferred until after M2.1. The need is real, but as designed it was
  hover-first in a keyboard-first app, underestimated (≈3 days, not 1–2), and
  one scroll away from the chat UI §2.2 forbids. Conditions if built:
  **keyboard-invoked** (palette switch-to rows or a chord), hard-capped at one
  paragraph, no scrolling. Re-evaluate first whether the Dock badge +
  elapsed-time hover already killed the need.
- **Designed sound** (two-note completion / question vocabulary; unseen-only
  routing) — the routing rule is right and the events exist, but the
  banner-sound vs. in-app-sound doubling must be resolved to **one audio
  path** first (bundle the designed sounds as `UNNotificationSound`s, *or* own
  playback and silence the banner — never both). The notes themselves are real
  design work on their own clock.
- **The promote transition, kernel only** — keep continuous identity (the
  landing terminal *becomes* the shell pane; recents fade; one fast ≤250 ms
  settle). No unfolding dividers, no spring theater.

## 8. Dropped (and why)

- **The promote choreography as a showpiece** (~350 ms documentary unfold) —
  wrong audience: it explains the promotion model to a first-time viewer who
  doesn't exist in an audience-of-one app, and taxes every session creation
  thereafter. Contradicts §1.1's own standard.
- **The animated `⌘\` layout reflow** — `⌘\` stays instant. Animating live
  terminal panes means animating stretched/stale bitmaps; for a
  dozens-of-times-daily operation, instant-and-correct beats
  smooth-and-smeared. *(Recorded dissent: a snapshot-slide variant — animate a
  static capture, swap in the live resized PTY at landing — would survive the
  critique. Revisit only if the instant toggle ever feels harsh.)*
- **The 15 ms fan row stagger** — below the liquidity threshold at four-to-six
  rows; reads as lag on a speed surface.

---

## 9. Order rationale & cost

Tokens before surfaces (everything reads from them; M2 inherits them). The
cockpit before the distances (in-window hours dwarf across-the-room glances,
and the non-key window state depends on the focus hairline existing). Distances
before arrivals (the Dock badge changes every day immediately; restore theater
changes one moment per day). Overlays last because they double as M2's first
component.

**Total: roughly two working weeks.** None of it blocks Milestone 2; Phase 0
accelerates it. Where the two design passes independently converged — the sine
colon, the ~4 s working pulse, materials codified in `Theme.swift` — the
agreement itself is evidence; where they diverged, this plan follows the
critique: *the distances won over the transitions.*
