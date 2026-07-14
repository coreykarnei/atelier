# 2026-07-13 — M2.1: the editor buffer

The placeholder era is over. The editor pane now hosts a real buffer —
**CodeEditSourceEditor 0.15** (`TextViewController`, TextKit 2) with
incremental tree-sitter highlighting, exactly the base TECHNICAL_PLAN §3.3
named. `EditorPlaceholderView` is deleted; `EditorPane` (WorkspacePane) takes
its slot in the triptych.

## What landed

- **Open/edit/save.** `⌘O` opens a file (NSOpenPanel rooted at the session's
  cwd — the native fallback until M2.2's `⌘P` summon picker), `⌘S` saves,
  edits mark the buffer dirty via a `TextViewCoordinator`. Opening from Split
  mode flips back to the Triptych so the buffer is actually on screen.
  Undo/Redo menu items route to the editor's `CEUndoManager` through the
  responder chain.
- **One Mocha (§2.9).** `Theme.Editor` carries the canonical Catppuccin Mocha
  code mapping (mauve keywords, blue functions, yellow types, green strings,
  peach constants, italic overlay0 comments), aligned with the terminals'
  ANSI palette. Background is `Theme.Elevation.base` at fieldAlpha — the
  editor is a field surface over the behind-window blur like every other.
  JetBrains Mono at terminal size. Minimap off; bracket-emphasis nil (the
  library default is a flash — a motion the inventory doesn't own).
- **Empty state** keeps the recessed-well look: crust, below the content
  plane, with a two-voice `⌘O open a file` line.
- **Dirty-close guard.** `⌘W` on a session with unsaved edits gets the
  informative refusal: the file named, the loss stated, "Save and Close" one
  button away.
- **Persistence.** `PersistedSession.openFile` (optional — old snapshots
  decode) reopens the buffer on restore. Verified live: a restored session
  came back with `Theme.swift` open, highlighted, gutter and current-line
  band correct.
- **Focus.** The editor participates in `⌃⌘hjkl` as before (its `focusView`
  is the text view once a file is open).

## Build system notes

- SwiftPM resource bundles (tree-sitter queries, editor assets) now ship in
  `Contents/Resources` — `Scripts/bundle.sh` copies `$BIN_DIR/*.bundle`.
  Without this, `Bundle.module` would crash at first highlight.
- **`Vendor/CodeEditSymbols`** is a local, committed copy of an upstream
  transitive dependency whose manifest never declares its `Symbols.xcassets`
  as a resource — it only builds under Xcode's implicit asset handling, and
  pure `swift build` fails on `Bundle.module`. The vendored copy declares the
  resource (one line) and drops the test target. SwiftPM resolves it over the
  remote by package identity; SwiftPM warns about the identity conflict today
  and may escalate it to an error in a future toolchain — if that lands,
  revisit (fork + pin, or upstream the fix).
- `swift build` can hold a stale manifest/product cache across a vendored
  manifest change — `rm -rf .build/manifests .build/<arch>/debug/<Pkg>*` was
  needed once.

## Residuals

- The syntax palette needs one live look (`commands` capture color, selection
  alpha) — snapshot proofing only goes so far.
- Worktree removal still discards a dirty buffer without naming it (its
  modal names uncommitted *git* changes only).
- App quit doesn't guard dirty buffers (⌘W does). Decide at M2.2 whether
  quit should sweep-save or refuse.
- The self-capture snapshot renders SwiftTerm panes mirrored in some states —
  snapshot artifact only; live rendering is fine. Worth a look eventually.
- Next: **M2.2 — `⌘P` fuzzy file picker on the summon idiom.**
