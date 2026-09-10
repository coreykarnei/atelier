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
