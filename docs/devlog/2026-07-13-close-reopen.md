# 2026-07-13 — Tab close `×` and reopen (`⌘⇧T`)

Owner request, verbatim intent: the selected session tab gets a little `×` at
its far left, before the title; clicking it closes the tab. And because an
easy click-to-close invites accidents, the browser's undo comes with it —
`⌘⇧T` reopens what was closed.

## What changed

- **The active tab — and only the active tab — carries a close `×`** at its
  leading edge, before the attention dot and title. Inactive tabs lost the old
  trailing `×` entirely: the tab you can close is the one you're looking at.
  The `×` rests at 0.55 alpha and reaches full strength under the pointer —
  opacity only, no color change, no motion (§1.3). Tab widths account for it,
  so activation glides a tab ~14 pt wider; the existing width-glide absorbs it.
- **`⌘⇧T` = Reopen Closed Session.** Each window keeps an in-memory stack
  (cap 10) of its closed *IDE* sessions — Landings are just shells and don't
  qualify. Reopen resurrects through the restore path: same
  `claude --resume <session-id>` the launch restore uses, back at its old tab
  position. Roots that vanished under the stack (worktree removed) are skipped.
  The stack deliberately dies with the window, like a browser's.
- **Undo restores the exact prior state:** closing the last session reverts the
  window to a Landing (unchanged); if that auto-created Landing is still the
  only tab when a reopen lands, the reopen *replaces* it instead of joining it.
- **`⌘⇧T`'s old job (new session on main) moved to `⌥⌘T`.** The keymap was
  [LOCKED], but the owner reached for `⌘⇧T` on browser instinct — which is the
  evidence the lock exists to protect. `⌘T`-new / `⌘⇧T`-reopen now matches
  browsers exactly. Menu, palette labels, and MILESTONE_1 §5/§6 updated; the
  menu item disables when the stack is empty.

## Notes

- The reopen snapshot is `PersistedSession` — the same struct launch restore
  uses, so the two paths can't drift.
- Shell state (history, cwd drift) does not survive a close/reopen; the shell
  restarts in the session's root. The agent conversation is the thing worth
  resurrecting, and it survives.
- Not persisted across app restarts for now; if that ever matters, the stack
  serializes trivially (it's already `PersistedSession`).
