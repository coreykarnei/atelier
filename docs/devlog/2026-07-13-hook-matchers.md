# 2026-07-13 — Residual retired: structured attention classification

The `needsInput`-vs-`waiting` split (§7.1's peach `!` vs plain dot) rested on
`message.body.lowercased().contains("waiting")` — a string sniff on Claude
Code's notification copy, flagged as fragile since the M1 polish pass.

Claude Code's Notification hooks support **matchers** (`permission_prompt`,
`idle_prompt`, …), so the classification now happens at the source:

- `Resources/hooks/atelier-hooks.json` registers two Notification entries —
  `permission_prompt` → `atelier-notify blocked`, `idle_prompt` →
  `atelier-notify waiting`.
- `NotifyMessage.Kind` gains `.blocked`; the app maps it straight to the `!`.
  The idle verb maps to plain waiting.
- The legacy unmatched form (`atelier-notify input`) still works — an
  un-migrated `~/.claude/settings.json` falls back to the old body sniff, and
  the new idle default body deliberately keeps the word "waiting" so both
  paths agree.

**Action needed once:** re-merge `Resources/hooks/atelier-hooks.json` into
`~/.claude/settings.json` (same manual-merge convention as the dotfiles
fragment) to get the structured split.
