# The `+` never asks — 2026-09-21

The session began with a question about one word. The worktree chooser's
first row read `fix/explorer-reload-storm — main checkout`, and the owner
asked why. Nothing was broken: the rows are labelled by branch, and the
primary checkout happened to be on a feature branch. But the question was
the right one, because that row is the only one in the list whose identity
*isn't* a branch. A linked worktree is one per branch — the name is the
place. The repo's own checkout is a place whose branch drifts.

So the row swapped its fields: `main checkout` in the chrome voice, the
branch trailing in dim mono. And then the real question surfaced.

## The tollbooth

The chooser was raised before *every* session — `+`, folder `+`, `⌥⌘T` —
and in the state that matters most it asked something the gesture had
already answered. Click a folder's `+` and you have said where. Press
`⌥⌘T` and you have said "another one of these". The card then asked
anyway, and defaulted to a phrase you had to decode.

The first fix proposed was to ask only when the gesture left it open: keep
the modal for the ambient `+`, skip it for a folder's. The owner killed
that immediately, and was right — `BottomBar` only draws folders once a
second group exists (`chunks.count > 1`, or a worktree/remote chunk), so
in the single-checkout case there is no ambient-versus-pointed distinction
to exploit. The rule would have changed nothing in exactly the state being
complained about.

That collapses the design space. The `+` has to mean one thing in both
modes, and the only meaning that isn't ceremony is *a session here*.

## The door

Branching then needs a front door, which it never had — creating a
worktree was two steps inside a modal you could only reach by trying to
start a session. The owner's shape: a second glyph beside the `+`, a tree
with a plus on it.

It reuses `FolderView.treePath`, the conifer that already labels worktree
folders, so the mark is the same species as the thing it makes. Noun then
verb, the way `folder.badge.plus` reads; two silhouettes, so the pair
never scans as two crosses. The inverse composition — a plus badged with a
tree — was built alongside and rejected on the strip: it read as a second
`+` with a smudge. The plus ended up laid *over* the tree rather than
badged at its shoulder, half the tree's width to the right so the conifer
survives, knocked out of it by a clear halo.

Gated on Settings → Enable worktrees *and* a repo project, so a bar that
never branches is exactly what it was before.

## What the card became

With `+` covering "here", a card raised to go elsewhere must not make the
main checkout a reflex `↩`. It opens naming a new worktree, with every
existing one listed beneath and the repo's own checkout last. Type and
`↩` creates; `↩` on an empty field starts the lit row; a click starts
that row outright.

That last one was a bug for an hour: clicking a row *armed* it and
required a second click, a leftover from when the dropdown was the only
way in — and arming put the now-redundant "New worktree…" row back on
screen. Two symptoms, one cause.

Hover went back and forth. Blocked first, because `↩` on an empty field
acts on the highlight and a resting pointer could arm main checkout
behind the reader's back; restored once typing was made to put the
highlight out, which removed the hazard and left pointer and keyboard
driving the same one thing.

## Measuring instead of nudging

Two placement faults were found by measuring rather than looking.

The card sat 40pt **below** centre. A positive `centerY` constant moves it
down in this layout; the constraint's comment had claimed "sits a little
above center" since it was written. With the old short card it read as
roughly centred, and only the taller list-bearing card made the droop
obvious. `probe:overlay` was added to dump a raised card's frame in window
points; it now reads 433 against the overlay's 393.

The tick before the `+` was seated centred in the lead gap, which is
correct in frame terms and wrong in ink terms: a tab's title stops 8pt
short of its chip, so the tick sat ~11pt from the text and 6pt from the
plus. Seated 1pt past the chip instead, the run measures title → 8.5 →
tick → 8 → `+` → 8.2 → `⎇+`.

## The scroll bug

Reported mid-session and unrelated: scrolling up while the agent was
mid-turn juddered, then snapped to the bottom.

`Terminal.scroll()` reads `Terminal.userScrolling` to decide whether to
follow output. Nothing writes it. `MacTerminalView` and `iOSTerminalView`
each declare a property of the same name, and only the scroller-thumb
path touches that one, so the wheel never reached the emulator: every
line of output ran `yDisp = yBase`. Each wheel tick fought the next feed,
and the feed won. `viewportHeldByUser` now answers positionally —
`yDisp < yBase`, the comparison xterm.js makes — and following resumes
when the reader returns to the bottom. The caret was the other half: it
was removed only when it sat *below* the viewport, so scrolled back it
stayed pinned to a row it had left. Vendored patch 8.

## Retired

The per-folder `+`'s whisper-at-rest (2026-09-17). It existed when
nothing else in the row was at full strength; beside a full-strength
`⎇+` a dimmed folder `+` was merely hard to see. One volume for every
`+` now, the hover pad doing the feedback.
