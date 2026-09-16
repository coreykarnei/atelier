# 2026-09-16 — Highlighting: it never ran, then twenty queries in parallel

The owner opened a buffer and read plain text. M2.1 had shipped "incremental
tree-sitter highlighting" two months ago, the editor built and ran, and no
grammar had ever coloured a single span. Not a theme bug, not a grammar bug
— a path. `CodeEditLanguages` resolves each query at a fixed
`Resources/tree-sitter-x/highlights.scm` under `Bundle.module.resourceURL`.
Under Xcode that URL is the bundle root, so the path is right; under
`swift build` it already *is* `<bundle>/Resources`, so the folder doubled,
every query URL pointed at nothing, and the library fell through silently
to unstyled text. Fixing the path took a handful of lines. Everything after
it was what the path had been hiding.

## What changed

- **`Vendor/CodeEditLanguages`** (0.1.20, upstream 331d5db) is the fourth
  vendored override, alongside SwiftTerm, CodeEditSourceEditor and
  CodeEditTextView. `queryURL(for:)` probes both bundle layouts and takes
  the one that exists. Its `ATELIER.md` lists six patches; the rest of them
  are query rewrites.
- **`Vendor/CodeEditSourceEditor`** grew four patches the same day (5–8 in
  its `ATELIER.md`): `EditorTheme.captures[CaptureName]` is consulted before
  the eight coarse slots; `CaptureName` learned the names the bundled queries
  actually emit (`function.builtin`, `constant`, `operator`, `punctuation`,
  `escape`, `type.builtin`, `attribute`, `namespace`, `label`…) with a
  dotted-prefix fallback; `highlightsFromCursor` keeps **one capture per
  range** — before, a generic `(identifier) @variable` and a specific
  `@function` were both emitted for the same node and the style container
  kept the first, so function names read as variables in every language
  with a catch-all pattern; ⌘F seeds from the selection.
- **`Theme.Editor`** carries catppuccin/nvim's per-capture Mocha mapping:
  keywords mauve, functions and methods blue, types yellow, constants /
  numbers / builtin functions peach, strings green, constructors and labels
  sapphire, properties and namespaces lavender, parameters maroon, `self` /
  `this` red, escapes pink, operators sky, punctuation overlay2, comments
  overlay0. Markdown: h1 lavender bold, h2–h6 blue bold, raw green (the
  preview's code colour), link text blue, url teal italic, list markers
  mauve, quotes overlay2 italic.
- **`EditorPane.captureAttributes`** is the `[CaptureName: Attribute]`
  table that binds the two: `keyword.function` and `include` italic (a
  declaration reads differently from control flow), comments italic,
  `markup.strong` bold, `markup.strikethrough` colour-only — the editor's
  `Attribute` has no strikethrough trait.
- **`atelier-hlcheck`** (`Sources/atelier-hlcheck`, `Scripts/hlcheck/`) —
  its own executable target. `swift run atelier-hlcheck <file>` does exactly
  what the editor does: combines the language's query files (parent +
  additional), compiles them against the *bundled* grammar, parses the
  file, resolves predicates, applies the one-capture-per-range rule, and
  prints `line:col  capture  → theme-capture  text` per span. `QUERY FAILED`
  names the offending line; in the app the same failure is silent and the
  whole language renders plain, so a red run is the gate. `--summary`
  totals by capture and lists *skipped* names — captures the editor has no
  slot for.
- **`Scripts/hlcheck/shadow.sh`** runs the prebuilt harness against
  *another checkout's* query files without a rebuild (below).
- **Twenty-four query folders** (the twenty fan-out languages plus python,
  rust and markdown-inline) now carry nvim-treesitter bucket names, each
  with a fixture in `Scripts/hlcheck/fixtures/` — 24 fixtures, all
  compiling with zero plain spans, jsx/tsx/markdown-inline included.
- **`CaptureName` aliases** from the merge: `type.definition → type`,
  `keyword.conditional.ternary → operator`, `function.method.call →
  method`; ten markup cases (`heading1`, `heading`, `strong`, `italic`,
  `strikethrough`, `raw`, `link`, `url`, `list`, `quote`) aliased from
  nvim's `markup.*` and the older `text.*`.
- **Dockerfile detection**: `Containerfile` and `*.dockerfile`, not just
  the bare name.

## The precedence rule

The Rust agent found it, and it reshaped every query after. The editor
keeps, per range, the capture with the lowest *capture index* — and
tree-sitter assigns that index to each distinct `@name` the first time it
appears in the combined query text. Pattern order is irrelevant. So

```
"for" @keyword                          ; line 10
(for_expression "for" @keyword.repeat)  ; line 200
```

paints `for` as plain `keyword`, because `@keyword` was mentioned first —
even though the second pattern is more specific and sits later. Every
rewritten query is therefore laid out in *name-priority order*: specific
buckets before `keyword`, `label` before `operator`, `punctuation.bracket`
before `operator`, `function.method` before `property`, `type.builtin`
before `type`, everything before `variable`. `tree-sitter-rust/highlights.scm`
is the worked example, its header spelling out the order.

Three consequences the README now documents:

- **Child queries combine ahead of their parent.** `tree-sitter-typescript`
  is concatenated *before* the JavaScript parent, so every name it
  mentioned first outranked the parent's — `(type_identifier) @type` beat
  constants, decorators and constructors (`GLOBAL_FLAG`, `@Component`,
  `new Shape<U>` all rendered as types). The fix is a short *preamble* that
  re-mentions the parent's high-priority names first.
- **A wide capture does not shade the leaves inside it.** Every range is
  painted, so tag the leaves. Markdown uses the flip side: headings are
  captured whole so marker + text read as one bold run.
- **A child query is compiled against its own grammar.** JavaScript's
  `(formal_parameters (identifier))` is structurally impossible under
  TypeScript and failed the whole combined query; parameters now use
  wildcard shapes valid in both.

## The fan-out

Two rounds, one agent per language, each in its own git worktree
(`worktree-wf_786dacef-80a-N`, then `worktree-wf_078ce0e6-4bd-N`), each
told the rule, the reference (nvim-treesitter, Helix for the older
grammars), the predicate set that resolves (`#match?`, `#eq?`,
`#not-match?`, `#not-eq?` — no `#any-of?`, `#lua-match?`,
`#has-ancestor?`), and the gate (a green hlcheck run on a dense fixture).
Each branch merged as a merge commit, then one fix-up commit per round.

| Round 1 | What the agent found |
|---|---|
| rust | stray `'` in the ALL_CAPS regex — constants never matched; the precedence rule |
| javascript / typescript / jsx | TS priority preamble; parameters valid in both grammars; jsx trimmed to tag/module/attribute |
| go | keyword split, builtins, constructors, members, doc comments |
| ruby | doc comments as parent-less sibling patterns; dropped an unresolvable `#is-not? local` that painted every parameter as a method |
| php | 8.0-era grammar; enum cases, namespaces as module, string interpolation as variables |
| java | methods/ctors/params/fields/constants/modules |
| c-sharp | 0.20-era grammar (`(modifier)`, `*_directive`, no `returns:`); 978 spans |
| c / cpp | C++ prepended to C; constructors from five shapes, `<=>`, `::`, `= default` |
| dart | priority-ordered so builtins/fields/params beat the catch-all |
| elixir | doc attributes as `comment.documentation`; helper captures bucket-named |
| ocaml | one file compiled against both `ocaml` and `ocaml_interface` |
| markdown | old `text.*` names placed nowhere; injection named `markdown_inline`/`yml` where Swift wanted `markdownInline`/`yaml`, so the inline grammar had never run |

| Round 2 | What the agent found |
|---|---|
| bash | builtins, keyword split, flags, expansion punctuation; then a follow-up: the backtick delimiter is one `` ` `` token, not two — the old pattern compiled and never matched |
| json | keys `property`, values `string`, `true`/`false` split from `null` |
| yaml | keys as property, `yes`/`no` boolean in value position only |
| toml | table headers `type` per segment, keys `property` at the leaf |
| css | selectors, at-rules, `--x` custom properties; a colour keeps its `#`, an id selector's `#` stays punctuation |
| html | entities as escapes, `h1`–`h6`/`title` inner text as `markup.heading`; `<style>` highlights through the css injection |
| dockerfile | `FROM`/`--from=` as `keyword.import`; heredocs dropped (grammar predates them) |
| go-mod | `require`/`replace` as import; `tool` directive dropped (grammar predates it) |

**What it cost.** Round 1 ran twelve `swift build`s in twelve worktrees and
filled the disk. The answer was `shadow.sh`: hard-link the main checkout's
prebuilt `atelier-hlcheck` into a scratch dir and stand a shadow
`CodeEditLanguages_CodeEditLanguages.bundle` beside it whose `Resources/`
is a *real* directory of per-grammar symlinks into the worktree's query
folders. A symlinked `Resources/` directory is invisible to CFBundle and a
symlinked binary resolves to its real path — hence real dir plus hard link.
It runs in under a second and tests exactly the files the editor would
load. A second fix located the main checkout through `git rev-parse
--git-common-dir` so the script works *from* a worktree. Round 2 was
build-free end to end. `.claude/worktrees/` is now gitignored.

## Gotchas

- **The harness lied once, and an agent believed it.** The php agent saw
  `injection.content → PLAIN` on every comment and heredoc (`injections.scm`
  is concatenated ahead of `highlights.scm`) and trimmed the injections.
  But the editor drops names `CaptureName.fromString` cannot place *before*
  the per-range contest, so `injection.*` never competes in the app; and no
  `phpdoc` grammar is bundled, so no sub-layer is ever created. The file
  was restored to upstream, and the harness now drops unmapped names before
  the contest too, reporting them as *skipped* rather than PLAIN.
- **Bundled grammars are older than the reference queries.** Rust has no
  `doc_comment`/`type_parameter`/`never_type`; JS has `(function)` not
  `(function_expression)`; TS has no `adding_type_annotation`; PHP is
  8.0-era; C# 0.20-era; dockerfile predates heredocs; gomod predates
  `tool`. One unknown node name fails the whole language silently in the
  app — hlcheck is the only place it shows.
- **A two-capture `#eq?` does not resolve** here; neither do nvim's
  `conceal`/`#set!` patterns.
- **`highlights-params.scm`** under tree-sitter-javascript is referenced by
  no language definition and was left alone.
- The markdown inline grammar shares the injection layer with the block
  query: an injected range is *removed* from the block query, so paragraph
  inlines are injected only under `section` / `list_item`, leaving heading
  and quote text in the block layer where their styling lives.

## Open

- **Upstreaming.** Patch 1 (the doubled `Resources/` path) is the one that
  matters to every SwiftPM consumer of CodeEditLanguages and should go up
  first; the one-capture-per-range and per-capture-theme patches to
  CodeEditSourceEditor next. The query rewrites are tuned to the older
  bundled grammars and may not apply upstream as-is.
- **Eleven grammars still wear their upstream queries** — swift among
  them, which is the one language the LSP client serves. Kotlin, lua,
  haskell, zig, scala, sql, objc, agda, jsdoc, regex likewise. Same recipe:
  fixture, `shadow.sh`, name-priority layout.
- The palette follows catppuccin/nvim verbatim; the italics on declaration
  keywords, imports and comments are the one taste call layered on top and
  await the owner's eye.
