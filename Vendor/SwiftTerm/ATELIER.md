# Vendored SwiftTerm

Upstream: https://github.com/migueldeicaza/SwiftTerm — tag `1.13.0`,
revision `8e7a1e154f470e19c709a00a8768df348ba5fc43` (2026-03-27).
Only `Sources/SwiftTerm` and `LICENSE` are carried; the manifest here is
Atelier's own (library target, macOS).

Why a copy rather than a dependency: the terminal is where terminal decisions
belong (Ghostty makes them inside its core), and SwiftTerm's AppKit view seals
the methods those decisions live in (`public`, not `open`). Patching from the
app side had started to pile up. Each patch below is meant to go upstream as
a PR; when one lands, drop it here and note the version.

## Local patches

1. **Wheel routing** (`Mac/MacTerminalView.swift`, `Terminal.swift`): mouse
   reporting on → wheel arrives as button 64/65 reports; alternate screen with
   `?1007` (alternateScroll) set → ↑/↓; otherwise local scrollback as before.
   `Terminal` now tracks DECSET/DECRST/DECRQM 1007.
2. **`open` view hooks** (`Mac/MacTerminalView.swift`): `scrollWheel`,
   `resetCursorRects`, `cursorUpdate` are `open` so hosts can customise them
   without swizzling.
3. **SGR motion encoding** (`Terminal.swift` `sendEvent`): a no-button
   motion report (any-event tracking, `?1003`) is `CSI <35;x;y M`, not a
   release `… m`. Claude Code 2.1.26x uses `?1003` for hover highlighting and
   read every hover as a click.
4. **`showsScroller`** (`Mac/MacTerminalView.swift`): hosts can drop the
   trailing legacy scroller; the grid takes the full width.
5. **`wheelPrecisionMultiplier`**: feel knob for trackpad wheel deltas
   (Ghostty's `mouse-scroll-multiplier.precision`), default 1.
6. **`copyOnSelect`** (`Mac/MacTerminalView.swift`): a finished mouse
   selection (drag, double/triple click) goes through `copy(_:)` — Ghostty's
   `copy-on-select = clipboard`. Off by default.
7. **OSC 52 forwarding** (`Mac/MacTerminalView.swift`): `TerminalView`'s
   `TerminalDelegate.clipboardCopy` now forwards to `terminalDelegate`; the
   request used to die in the protocol's empty default, so the local-process
   view's pasteboard write never ran.

8. **Scrollback holds under streaming output** (`Terminal.swift`,
   `Apple/AppleTerminalView.swift`; owner report 2026-09-21: scrolling up
   while Claude is mid-turn juddered and then snapped to the bottom).
   `Terminal.userScrolling` was read in `scroll()` but *never written* —
   `MacTerminalView` and `iOSTerminalView` each declare a same-named
   property of their own, and only the scroller thumb path
   (`scroll(toPosition:)`) touches that one, so the wheel never reached the
   emulator. Every line of output therefore ran `buffer.yDisp = buffer.yBase`
   and yanked a scrolled-back reader down; each wheel tick fought the next
   feed, which is the judder. `viewportHeldByUser` now answers the question
   positionally — the flag, or `yDisp < yBase` — the way xterm.js compares
   `ydisp` to `ybase`, and `scroll()` consults it in all three places.
   Following resumes on its own the moment the reader returns to the bottom.
   Second half: `updateCursorPosition` removed the caret only when the
   cursor sat *below* the viewport, so scrolled back it stayed pinned to a
   row it had left, drifting with each new line. It now leaves on either
   edge.
9. **Typing returns to the live view** (`Mac/MacTerminalView.swift`
   `ensureCaretIsVisible`; owner report 2026-09-21: text typed while scrolled
   back sometimes never appeared). Upstream snapped to the bottom on a
   keystroke only when the caret's own row had left the viewport. Once
   patch 8 made the hold real, a reader scrolled back only a little kept
   the caret row on screen, so the snap never fired, the hold stayed, and
   the next line of output (a wrapping prompt, Claude repainting below the
   caret) landed under the bottom edge. Any keystroke now releases a held
   viewport, as in iTerm2 and Ghostty (the iOS view already jumped
   unconditionally).
10. **Row render cache** (`Apple/RowRenderCache.swift`,
    `Apple/AppleTerminalView.swift`, `BufferLine.swift`,
    `Mac/MacTerminalView.swift`; owner report 2026-09-23: Claude scrolling
    and window resizes felt sluggish). Every CPU draw rebuilt every visible
    row's attributed string, shaped it with CoreText and bridged each run's
    attributes — about half the draw. Rows are now kept by content: the key
    is the row's raw cell bytes plus everything else the build reads (cols,
    the row's selection span, link-hover state, bright-colour and
    custom-glyph flags); fonts, palette and selection colour clear the
    store. A row that only moved (scrollback, a TUI repainting shifted
    lines) skips straight to glyph drawing. Rows with images or kitty
    placeholders bypass it. Measured scrolling Claude's pane: ~22ms → 12–15ms
    per draw. `RowRenderCache.isEnabled` switches it (A/B), and
    `TerminalView.drawObserver` reports each draw's duration.
