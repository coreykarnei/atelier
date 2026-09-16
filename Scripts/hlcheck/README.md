# hlcheck — test a highlight query without the app

```
swift run atelier-hlcheck Scripts/hlcheck/fixtures/python.py
swift run atelier-hlcheck some/file.ts --summary
swift run atelier-hlcheck file.txt --lang rust
# From a worktree, without rebuilding: the main checkout's binary against
# THIS checkout's query files (Resources/ symlinked per grammar).
Scripts/hlcheck/shadow.sh . Scripts/hlcheck/fixtures/ruby.rb --summary
```

`shadow.sh` is the loop to use when several checkouts are being edited at
once — twelve parallel `swift build`s once filled the disk; the shadow runs
in under a second and tests exactly the files the editor would load.

It does exactly what the editor does: combines the language's query files
(parent + additional), compiles them against the *bundled* grammar, parses
the file, resolves predicates, and applies the editor's one-capture-per-range
rule. Output is one line per span: `line:col  capture  → theme-capture  text`.

What to look for:

- **`QUERY FAILED`** — a pattern names a node or field the bundled grammar
  doesn't have. In the app this fails silently and the whole language renders
  plain, so a red run here is the gate.
- **`skipped captures`** — the query emits names the editor has no slot for
  (`injection.content` from a merged `injections.scm` is expected; anything
  else is a bucket you meant). The editor drops these *before* choosing a
  winner per range, and so does this tool, so a skipped name never hides a
  real capture. Rename it in the query to one `CaptureName.fromString` knows
  (`Vendor/CodeEditSourceEditor/.../Enums/CaptureName.swift`) or add an alias
  there.
- The right spans on the right words: `def`/`fn`/`func` as
  `keyword.function`, control flow as `conditional`/`repeat`/`keyword.return`,
  imports as `include`, function names as `function`/`function.method`,
  builtins, parameters, properties, constructors, types.

**Precedence is by capture *name*, not pattern order.** The editor keeps,
per range, the capture with the lowest capture index — and a capture index
is assigned to each distinct `@name` the first time it appears in the
combined query text. So `(for_expression "for" @keyword.repeat)` loses to
a bare `"for" @keyword` if `@keyword` was mentioned *anywhere earlier* in
the file, no matter where the two patterns sit. Lay a query out so the
first mention of each name follows the priority you want (specific buckets
before `keyword`, `label` before `operator`, `punctuation.bracket` before
`operator`, `function.method` before `property`, `type.builtin` before
`type`, everything before `variable`); `tree-sitter-rust/highlights.scm`
is the worked example, and `tree-sitter-typescript/highlights.scm` shows
the trick for a child query that is combined *ahead of* its parent: a short
preamble that re-mentions the parent's high-priority names first. Two more
consequences: a wide capture does not shade narrower ones inside it (every
range is painted, so tag the leaves), and a child query is compiled against
its own grammar, so a pattern that is structurally impossible there
(JavaScript's `(formal_parameters (identifier))` under TypeScript) fails
the whole combined query.

Fixtures live in `fixtures/` — one representative file per language, dense
with the constructs above. Queries live in
`Vendor/CodeEditLanguages/Sources/CodeEditLanguages/Resources/tree-sitter-<lang>/`.
nvim-treesitter's queries are the reference for bucket names; strip
`#lua-match?`/`#any-of?` predicates (only `#match?`, `#eq?`, `#not-match?`,
`#not-eq?` resolve here) and check node names against the bundled grammar by
running this tool.
