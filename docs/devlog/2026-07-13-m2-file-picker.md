# 2026-07-13 — M2.2: `⌘P`, the file summon

The payoff of the summon extraction: the fuzzy file picker is ~150 lines,
because the interaction already existed.

## What landed

- **`SummonCardOverlay`** (OverlayChrome.swift): the palette's floating
  chrome — scrim, hud-blur card descending from the titlebar, top hairline,
  content-hugging height — extracted as the shared card. `CommandPalette`
  collapsed onto it (it's now just command semantics); `FilePicker` is its
  second host. One silhouette for every summoned surface.
- **`⌘P` — Go to File** (`FilePicker.swift`): the card over the repo's files
  via `git ls-files --cached --others --exclude-standard` (tracked +
  untracked, `.gitignore` respected — TECHNICAL_PLAN §3.4's contract),
  gathered off-main so a big repo can't stall the descent. Recently opened
  files (per repo root, `RecentFilesStore`) render instantly and lead the
  offer; the query fuzzy-matches the whole relative path, so `tvc` finds
  `.../TextViewController.swift`. Row anatomy matches the landing: mono
  name leading, muted dir behind. Activation records the recent, opens the
  buffer, focuses the editor.
- **The one buffer is guarded everywhere:** opening over unsaved edits (via
  `⌘P` or `⌘O`) now gets the same informative refusal closing does —
  `guardDirtyBuffer` is one shared path with "Save and …" a button away.
- Menu: View → "Go to File…" `⌘P` (disabled outside IDE sessions); palette:
  "Editor: Go to File…".

## Verified live

Driven by real keystrokes: `⌘P` descended the card over the editor with the
repo's files listed; typing `landingv` + `↩` swapped the buffer to
`LandingView.swift`, highlighted, caret at 1:1. The chrome, filter,
activation, dirty-guard wiring, and recents all rode the already-reviewed
summon machinery.

## Residuals

- Match *ranking* is provider-order + subsequence filter — no fzf-style
  scoring yet (basename hits should outrank path-scatter hits). Revisit when
  it misfires in practice; the hook is a host-supplied ranker on SummonList.
- The picker lists the session root's files; multi-root (worktree sibling
  files) is deliberately out — one session, one root.
- Next: **M2.3 — `⌘⇧F` repo search + results panel.**
