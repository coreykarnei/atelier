; JSON highlights — Atelier revision.
;
; The editor keeps one capture per range, and the winner is the capture NAME
; mentioned earliest in this file (pattern order is irrelevant). Laid out in
; priority order:
;
;   comment · property · string.escape · boolean · constant.builtin · number ·
;   string · punctuation.delimiter · punctuation.bracket
;
; Keys read as structure (property); string VALUES read as prose (string) —
; the key pattern is narrower than the catch-all (string), and `property`
; is mentioned first so it wins the shared range. Escapes are tagged before
; `string` so they show inside both keys and values.
;
; Bucket names are nvim-treesitter's (Helix layout), restricted to what
; CaptureName.fromString places; only #match?/#eq?/#not-match?/#not-eq?
; resolve, so nvim's conceal/#set! patterns are dropped. Checked against the
; bundled grammar with Scripts/hlcheck.

; -------
; Comments (jsonc)
; -------

(comment) @comment

; -------
; Keys
; -------

(pair
  key: (string) @property)

; -------
; Literals
; -------

(escape_sequence) @string.escape

[
  (true)
  (false)
] @boolean

(null) @constant.builtin

(number) @number

(string) @string

; -------
; Punctuation
; -------

[
  ","
  ":"
] @punctuation.delimiter

[
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket
