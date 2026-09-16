; go.mod highlights — Atelier revision.
;
; The editor keeps one capture per range: the capture NAME mentioned first in
; this file wins, regardless of pattern order (see Scripts/hlcheck/README.md).
; Names therefore appear in priority order:
;
;   comment · string.escape · number · keyword.import · keyword · string ·
;   punctuation.bracket · punctuation.delimiter · operator
;
; Bucket names are nvim-treesitter's, restricted to what CaptureName.fromString
; places. Only #match? / #eq? / #not-match? / #not-eq? predicates resolve.
; Checked against the bundled grammar with Scripts/hlcheck (older
; tree-sitter-go-mod: no `tool` directive / (tool) node).

; -------
; Comments — `// indirect` trailers included
; -------

(comment) @comment

; -------
; Versions: `v1.8.1`, pseudo-versions, `+incompatible`, the `go 1.22.3`
; version and the `toolchain go1.22.5` name all read as numbers.
; -------

(escape_sequence) @string.escape

[
  (version)
  (go_version)
  (toolchain_name)
] @number

; -------
; Directives
; -------

[
  "require"
  "replace"
] @keyword.import

[
  "module"
  "go"
  "toolchain"
  "exclude"
  "retract"
] @keyword

; -------
; Module paths and replacement file paths
; -------

[
  (module_path)
  (file_path)
  (interpreted_string_literal)
  (raw_string_literal)
] @string

; -------
; Punctuation and the replace arrow
; -------

[
  "("
  ")"
  "["
  "]"
] @punctuation.bracket

"," @punctuation.delimiter

"=>" @operator
