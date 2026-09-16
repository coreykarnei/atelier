# 2026-09-15 — The file explorer, and the editor made to behave

The editor had a buffer, a picker, a repo search and a language server, but
no way to *see* the repo — every file arrived through `⌘P`. This pass gave
the pane a VSCode-shaped Explorer down its left edge, then chased every
editor complaint that surfaced while using it: lines that ran off the right
with nothing to scroll into, clicks that landed a column left of the
pointer, a viewport that yanked itself to the margin when you typed, and a
`⌘Z` that did nothing after duplicating a line. Two owner calls landed
mid-build — typing into a preview should *enter* the file, and the
sidebar's search is two toggles, not a mode switch.

## What changed

- **`FileExplorer.swift`** — `FileExplorerView`, 220pt in the editor pane's
  left edge, rooted at the session's cwd (a worktree session shows the
  worktree). Lazy children; `.git` hidden; gitignored paths dimmed from one
  `git status --porcelain --ignored -z` per reload (untracked-but-not-ignored
  stays bright — those are the files you're making). An FSEvents stream on
  the root keeps it live with expansion and selection preserved.
- **Preview → commit.** Single click previews the file soft-wrapped with
  focus left in the tree; double-click or `↩` commits — editable, unwrapped,
  the language server told — and the tree folds to a 26pt rail whose chevron
  (or `⌘B`) brings it back. `⌘P`/F12 opens fold it the same way. Previews stay
  out of persistence and never go dirty. Arrowing through the tree previews
  files as you pass them (keyboard only; clicks and programmatic reselects
  don't). Typing into a preview first committed *quietly* (real buffer, no
  unwrap, no fold); by evening, per owner call, it commits exactly like
  double-click — one `commitPreview()` path.
- **The search panel.** `RepoFileOffer` (`FilePicker.swift`) extracts `⌘P`'s
  `git ls-files` gathering, row anatomy and ranking; `RepoTextSearch`
  (`RepoSearch.swift`) extracts `⌘⇧F`'s debounced ripgrep / `git grep`
  engine. The sidebar hosts one `SummonList` over both: the header's
  magnifier, `⌘⇧E`, or the palette opens it in place of the tree with
  **Files** and **Text** toggles (remembered, both on by default — the owner
  rejected a mode switch). File matches filter locally and land at once
  (capped at 40 while a query is live); ripgrep hits append beneath as
  two-line rows (`SummonItem` gained a detail line, `SummonList` per-row
  heights); stale text results for an older query are dropped. Arrowing
  through results previews the row — a file, or the file at the hit's
  line:column — without leaving the field, and never raises the save
  dialog. `SearchHit` carries its length so the editor reveals with a
  `⌘F`-style emphasis at the match and the row renders the matched text
  semibold. Esc clears, then closes; collapsing the rail closes too.
- **Sticky folder headers and indent guides.** The ancestor chain of the row
  under the tree's top edge stays pinned as mirrored rows on an opaque crust
  strip with a hairline (translucent showed rows through the names); click
  one to jump back to that folder. Guides are a hairline under each
  ancestor's chevron down every nested row; an expanded folder draws the top
  segment from just below its own chevron, so the line runs unbroken from
  caret to last child — through the pinned stack too. The stack hides on
  the rail and in search, and lives inside the scroll view beneath its
  scroller so the scrollbar always draws on top.
- **Context menu.** Right-click a row (or empty space for the root): New
  File / New Folder open a placeholder row with its name field live — `↩`
  creates on disk (a new file opens for real), Esc or empty removes the
  row; Rename edits in place with the stem preselected and, if the open file
  or its folder moved, the buffer follows (watcher re-armed, server told);
  Move to Trash confirms in a sheet; Reveal in Finder; Copy Path / Copy
  Relative Path.
- **Disk watch.** A vnode source follows the open file (write / extend /
  delete / rename / revoke). Git and most editors replace by rename, so on
  delete/rename the watch re-arms on the path a beat later. A clean buffer
  takes the new text with caret and scroll preserved and tells the server;
  a dirty buffer keeps its edits — nothing is discarded silently.
- **Autosave.** `Settings.autosave` — a Settings checkbox and a File →
  Autosave checkmark item, one switch. On, the buffer writes 0.8s after each
  edit and the dirty guard saves instead of asking.
- **File header.** `EditorFileHeader`, a 26pt mantle strip over the buffer:
  path from the root in mono, a dot while dirty, and for markdown a Text /
  Preview toggle (remembered). `MarkdownPreviewView` renders the live buffer
  through Foundation's full-syntax markdown parser, dressed in Mocha —
  headings, lists, quotes, code blocks, tables, links — in a selectable
  read-only text view, re-rendered 250ms after each edit and on type-scale
  change. `< >` history followed (committed opens recorded, `⌃⌘←`/`⌃⌘→` in
  View, back/forward through the dirty guard); the editor subtree now
  `clipsToBounds` so the gutter can't paint over the header.
- **`DiagnosticStrip`.** One line floating over the bottom of the buffer:
  severity dot plus the server's message for the caret's line
  (range-containing first, errors before warnings). Hidden in previews and
  when the caret is elsewhere; floating so text never reflows as it appears.
- **VSCode chords** (vendored CodeEditSourceEditor): `⌥⌘↑/↓` caret above /
  below, `⇧⌥↑/↓` duplicate lines, `⌥↑/↓` move lines (the methods existed,
  unbound), `⌘D` select next occurrence (word first on a bare caret); the
  find field reads `3/10` instead of a bare count. Vendored CodeEditTextView:
  `⌥-click` adds a caret alongside `⌃⇧-click`. `⌘-click` and `⌘-hover` ride the
  library's `JumpToDefinitionModel` — the controller now exposes its delegate
  to AppKit (patch 8), the hover asks the delegate before promising a link
  (an identifier with no definition keeps the arrow), caches it for the
  click, underlines in the theme accent. `EditorPane` is the delegate over
  the LSP client; the interim `onCommandClick` hook is retired.
- **`LSPServers`** (`LSP.swift`) — a `Spec` per tree-sitter language the
  editor knows, with ordered server candidates (pyright / basedpyright /
  pylsp, typescript-language-server, rust-analyzer, gopls, clangd, ruby-lsp,
  zls, marksman, taplo, …). The search path is the owner's login-shell PATH
  (`zsh -lic 'echo $PATH'`, probed once), then the app's own, then the usual
  tool bins; the first installed candidate wins, cached per key, one client
  per (root, language). Nothing installed → the editor stays plain. Python
  servers get the repo's venv: `.venv`/`venv` at the root, one level down,
  or the main checkout's for a worktree, answered as `workspace/configuration`
  section `python` (`pythonPath` + `analysis.extraPaths`) and pushed once via
  `didChangeConfiguration`; the process runs with the venv's bin first on
  PATH and `VIRTUAL_ENV` set. `ATELIER_LSP_TRACE=1` logs server→client
  requests and our answers to `~/.local/state/atelier/lsp.log`.
- **Gutter** 68pt → 47pt: fold ribbon off (11pt for folding we haven't
  wired), insets 10/12 instead of upstream's 20/12 — taste, noted in
  `ATELIER.md` as not an upstream candidate.
- **`SplitCornerHandle`** (`Layout.swift`): an 18pt handle where the
  triptych's dividers cross — crosshair cursor, one drag moves both,
  clamped to slot minimums, PTY resizes frozen for the drag.
- **Dev probes** over the socket: the snapshot dumps the buffer's scroll
  geometry, hit-test winners across the editor's width and the minimap's
  hidden state; `toggleExplorer`, `explorerSearch` (with a trailing `↓` and
  a prefix that expands folders), `probe:diag`, `probe:links`,
  `probe:resize`, `probe:back/forward`, `probe:dupundo/keys/steps`.

## What we learned

- **Four vendored fixes, each in the library because the bug is in the
  library.** `Vendor/CodeEditTextView` (0.12.1) and
  `Vendor/CodeEditSourceEditor` (0.15.2) join `CodeEditSymbols` as local
  overrides by package identity; each carries an `ATELIER.md` listing its
  patches, every one meant for upstream.
  1. *Long lines never scrolled.* `layoutLine` took the widest-line
     accumulator `inout`, then declared `var maxFoundLineWidth =
     maxFoundLineWidth` — every update landed on the local copy, so
     `maxLineWidth` stayed 0 and the frame never grew past the viewport.
     Deleting the shadowing line is the whole fix. Still on upstream `main`.
  2. *The right 17% of the editor couldn't be clicked.* The hidden minimap's
     `hitTest` returned `self` without checking `isHidden`; as a floating
     subview of the scroll view it is consulted while hidden. Returns nil now.
  3. *Typing over a selection snapped the view to x = 0.* Scroll-to-visible
     followed the selection's bounding box, which with wrapping off spans
     the whole document width; a rect wider than the clip scrolls to the
     origin. Both sites use `caretRect(for:padded:)`: visibility tested with
     the bare caret (an on-screen caret never moves the view), the reveal
     with a padded one — a quarter of the viewport sideways (24…160pt), one
     line up and down — so an off-screen caret lands with room, the
     VSCode/Sublime manner.
  4. *`⌘Z` after `⇧⌥↓` did nothing.* `ViewReuseQueue` recycled line-fragment
     views by setting `isHidden = true` on a subview of the first-responder
     text view; AppKit's `_setHidden:`, running inside the key event, moved
     first responder to the window, so undo had no target. Direct method
     calls never reproduced it — only synthesized key events through
     `NSApp.sendEvent` did. Layout re-adds every fragment view it uses, so
     `removeFromSuperviewWithoutNeedingDisplay` is equivalent and
     side-effect free.
- **Our own `git status` fed a reload loop.** Refreshing ignore state
  touched `.git/index`, FSEvents saw it, the tree reloaded and re-scrolled
  to the open file — fighting every upward scroll. Events under `.git` are
  ignored (CF-typed paths, prefix test) and background reloads reselect
  without scrolling.
- **Don't set a constraint constant inside `layout()`.** The search list's
  height changed there and never triggered the follow-up pass, so the list
  sat at 0pt, results clipped under the field and the whole bar could
  vanish. It's now set when the query flips between empty and live, from
  the field block's measured height; later the open panel pins to the
  bottom edge outright so a window resize can't leave the toggles over the
  header.
- **A scroll-view setting written before `loadView` lands on nil.**
  `usesPredominantAxisScrolling = false` (the plane shouldn't lock to an
  axis with wrapping off) did nothing until it followed the `addSubview`
  that loads the controller's view.
- **`NSSplitView` claims a band around its divider before asking
  subviews**, so grabbing the crossing moved one divider. The outer split's
  `hitTest` hands the handle's rect to the handle.
- **`reloadItem(nil, reloadChildren:)` wrecks the outline's row model** —
  every label and chevron vanished after New File at the root. Root reloads
  use `reloadData`; folders keep `reloadItem`.
- **AppKit skips `drawBackground` on a clear table**, so indent guides are
  drawn in the row view's `draw` pass. The guide x is read off the outline's
  real disclosure frame — the hard-coded 8pt was a hair off the chevron.
- **The library's gutter floats over the text with the pane's translucent
  fill**, so text scrolled under it showed through the numbers. The text
  view's layer wears a mask from the gutter's right edge that follows the
  clip's horizontal offset.
- **Arrow key events carry `.function` and `.numericPad`** — strip them before
  matching a chord's modifiers. And `⌥⌘↑/↓` drifted a column left per press
  because it probed mid-glyph; it probes the caret's leading x now and merges
  into existing carets.

## Open

- M2.4's feel-check is still the owner's: the chords, `⌥-click` carets and
  `⌘D` are in, untried by the hand they're for.
- Folding is off (ribbon hidden) and unwired.
- The vendored patches wait on upstream PRs; TextView patch 1 was still on
  upstream `main` as of 2026-09-15.
- Highlighting turned out to have never worked — that's the next entry.
