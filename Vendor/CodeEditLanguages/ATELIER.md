# Atelier patches to CodeEditLanguages

Vendored copy of CodeEditLanguages 0.1.20 (upstream 331d5db), used as a
local path override — the same pattern as `Vendor/SwiftTerm`. Each patch is
meant for an upstream PR.

1. **Query URL resolved against both bundle layouts** (`CodeLanguage.swift`,
   `queryURL(for:)`). `Bundle.module.resourceURL` is the bundle root under
   Xcode but `<bundle>/Resources` under `swift build`, so the fixed
   `Resources/tree-sitter-x/highlights.scm` path doubled the folder and no
   highlight query loaded in SwiftPM-built apps. Probe both, prefer the one
   that exists.
2. **Python keyword buckets split** (`Resources/tree-sitter-python/
   highlights.scm`): `def`/`class`/`lambda` → `@keyword.function`,
   `return`/`yield` → `@keyword.return`, `if`/`elif`/`else`/`match`/`case` →
   `@conditional`, `for`/`while` → `@repeat`, `import`/`from` → `@include`.
   Same buckets nvim-treesitter uses; lets a theme colour declarations
   apart from control flow. (Word operators were already `@operator`.)
3. **Rust query rewritten** (`Resources/tree-sitter-rust/highlights.scm`).
   The shipped query had a stray `'` inside the ALL_CAPS regex
   (`"^[A-Z][A-Z\\d_]+$'"`), so no constant ever matched; every keyword sat
   in one bucket; `use`/`mod` paths, lifetimes, closures and method calls
   were unhighlighted or wrong. Rewritten on Helix's rust query, bucketed
   nvim-style (`keyword.function/import/conditional/repeat/return/operator`,
   `function.macro/method/builtin`, `namespace`, `label`, `property`,
   `variable.parameter`, `type.builtin` for std prelude names), limited to
   the node names the bundled (older) grammar has — no `doc_comment`
   markers, `type_parameter`, `never_type`, `raw`/`gen`. Ordered by
   *capture-name first mention*, because the editor keeps the capture with
   the lowest capture index per range (see the header comment there and
   `Scripts/hlcheck/README.md`). Fixture: `Scripts/hlcheck/fixtures/rust.rs`.
4. **Twelve more queries rewritten to nvim-treesitter buckets** (2026-09-16,
   one agent per language, each verified with `atelier-hlcheck` against the
   bundled grammars): javascript + typescript (+ jsx trimmed), go, ruby, php,
   java, c-sharp, c + cpp, dart, elixir, ocaml, markdown + markdown-inline.
   Same rules as patch 3: `#match?`/`#eq?` predicates only, node names
   limited to what the bundled (often older) grammars have, capture names
   laid out by first mention for the editor's lowest-capture-index rule.
   Fixtures for each live in `Scripts/hlcheck/fixtures/`. Markdown also
   gains a working `markdown-inline` injection and markup captures
   (`markup.heading`, `markup.strong`, `markup.italic`, `markup.raw`,
   `markup.link`, `markup.list`, `markup.quote`…) that
   CodeEditSourceEditor's `CaptureName` now knows.
5. **Config and markup queries rewritten** (2026-09-16, second fan-out,
   verified build-free with `Scripts/hlcheck/shadow.sh`): bash, json, yaml,
   toml, css, html, dockerfile, go-mod. Keys/properties distinct from string
   values (json/yaml/toml), tags/attributes/entities (html), selectors,
   at-rules and custom properties (css), builtins/flags/expansions (bash),
   instructions/image specs/flags (dockerfile), directives/versions (go-mod).
   Fixtures in `Scripts/hlcheck/fixtures/`.
6. **Dockerfile detection** (`CodeLanguage+Definitions.swift`): `Containerfile`
   and the `.dockerfile` extension detect as dockerfile, not just the bare
   `Dockerfile` name.
