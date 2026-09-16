; TOML highlights — Atelier revision.
;
; The editor keeps one capture per range, and the winner is the capture whose
; NAME is mentioned first in this file (pattern order is irrelevant). Names
; therefore appear in priority order:
;
;   comment · string.escape · type (table headers) · boolean · number.float ·
;   number · string.special (dates/times) · string · property (keys) ·
;   punctuation.bracket · punctuation.delimiter · operator
;
; Ported from nvim-treesitter (bucket names) and Helix (headers as @type).
; Keys are tagged at the leaf — each bare/quoted segment of a dotted key gets
; its own span, and the `.` between them stays a delimiter. The bundled
; grammar nests `dotted_key` left-recursively (a.b.c is
; dotted_key(dotted_key(a . b) . c)) and queries only see direct children, so
; header segments are enumerated to four levels deep; deeper headers fall to
; the key colour. Only #match? / #eq? / #not-match? / #not-eq? predicates
; resolve. Checked against the bundled grammar with Scripts/hlcheck.

; -------
; Comments
; -------

(comment) @comment

; -------
; Escapes inside strings (tagged before the string itself)
; -------

(escape_sequence) @string.escape

; -------
; Table headers: [a.b] and [[a.b]] read as types, segment by segment
; -------

(table [(bare_key) (quoted_key)] @type)
(table (dotted_key [(bare_key) (quoted_key)] @type))
(table (dotted_key (dotted_key [(bare_key) (quoted_key)] @type)))
(table (dotted_key (dotted_key (dotted_key [(bare_key) (quoted_key)] @type))))
(table (dotted_key (dotted_key (dotted_key (dotted_key [(bare_key) (quoted_key)] @type)))))

(table_array_element [(bare_key) (quoted_key)] @type)
(table_array_element (dotted_key [(bare_key) (quoted_key)] @type))
(table_array_element (dotted_key (dotted_key [(bare_key) (quoted_key)] @type)))
(table_array_element (dotted_key (dotted_key (dotted_key [(bare_key) (quoted_key)] @type))))
(table_array_element (dotted_key (dotted_key (dotted_key (dotted_key [(bare_key) (quoted_key)] @type)))))

; -------
; Literals
; -------

(boolean) @boolean
(float) @number.float
(integer) @number

[
  (offset_date_time)
  (local_date_time)
  (local_date)
  (local_time)
] @string.special

(string) @string

; -------
; Keys — every bare or quoted segment not claimed by a header above
; -------

[
  (bare_key)
  (quoted_key)
] @property

; -------
; Punctuation
; -------

[
  "["
  "]"
  "[["
  "]]"
  "{"
  "}"
] @punctuation.bracket

[
  "."
  ","
] @punctuation.delimiter

"=" @operator
