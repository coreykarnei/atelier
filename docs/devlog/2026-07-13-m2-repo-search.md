# 2026-07-13 — M2.3: `⌘⇧F`, find in repo

The third summon card, and the first *externally-filtered* one: the query
doesn't filter the offer, it **produces** it.

## What landed

- **`SummonList` external-filter mode** (`filtersLocally: false` +
  `onQueryChange`): the host owns result production; the list keeps
  everything else — focus discipline, arrows, single-click, no-match line,
  content-hugging card.
- **`RepoSearchOverlay`** (`⌘⇧F`): each keystroke (debounced 150 ms) shells
  out to **ripgrep** — fixed-string, smart-case, line+column — falling back
  to `git grep -In --column -F` when rg isn't installed (TECHNICAL_PLAN
  §3.5's candidate, exactly). Results render as `name:line` + muted snippet,
  capped at 300 with an honest "… more matches — narrow the query" tail row.
  In-flight processes are terminated when superseded. `↩` opens the hit in
  the buffer **at its line and column** (`EditorPane.reveal`), through the
  same dirty-buffer guard as every open.
- The fixed pane shape stays fixed: results live on the card, not a fourth
  panel — the plan's "results panel" reinterpreted through the summon idiom
  the palette and `⌘P` already speak. The card runs taller here (19 rows).

## Verified live

Real keystrokes end to end: `⌘⇧F` descended the card; typing
`effectiveFieldAlpha` produced four hits (TerminalPane.swift:97,
Theme.swift:19, Theme.swift:59, POLISH_PLAN.md:116) with snippets; `↓` `↩`
landed the buffer on Theme.swift with the current-line band exactly on
line 19.

## Residuals

- Search-in-progress shows the previous offer until results land (Spotlight
  behavior); an explicit "searching…" state wasn't needed at repo scale but
  might be at monorepo scale.
- No per-file grouping or match-count header yet; flat rows read fine at the
  cap. Revisit with real use.
- Next: **M2.4 — multi-cursor / drag-select / find-replace** (largely
  wiring: CodeEditTextView carries multi-cursor natively; the controller
  ships a find panel).
