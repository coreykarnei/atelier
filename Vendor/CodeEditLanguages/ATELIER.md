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
