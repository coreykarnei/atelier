; CSS highlights — Atelier revision.
;
; The editor keeps one capture per range: the capture whose NAME is first
; mentioned earliest in this file (pattern order is irrelevant, see
; Scripts/hlcheck/README.md). This file is therefore laid out in priority
; order:
;
;   comment · string · number.float · number · keyword.import ·
;   keyword.operator · keyword.modifier · attribute · function.call ·
;   variable · constant · namespace · tag · type · property · keyword ·
;   punctuation.bracket · punctuation.delimiter · operator
;
; Consequences worth knowing: `attribute` ahead of `tag`/`type` so `::before`
; and `:hover` read as pseudo-selectors, not as elements/classes; `variable`
; ahead of `property`/`constant` so `--x` custom properties win both where
; they are declared and where `var(--x)` reads them; `constant` ahead of
; `punctuation.delimiter` so a colour's leading `#` stays part of the colour
; while an id selector's `#` stays punctuation; `string` ahead of `constant`
; so an unquoted attribute value (`[type=text]`) reads as a string.
;
; Ported from nvim-treesitter's and Helix's css queries, reduced to the
; predicates this editor resolves (#match?/#eq?/#not-match?/#not-eq?) and
; the captures it can place. Checked against the bundled grammar with
; Scripts/hlcheck.

; -------
; Comments
; -------

(comment) @comment

; -------
; Literals
; -------

(string_value) @string
(attribute_selector (plain_value) @string)

(float_value) @number.float
(integer_value) @number
(unit) @number

; -------
; Keywords the theme draws apart from the plain keyword bucket
; -------

"@import" @keyword.import

; media / supports query logic
[
  "and"
  "or"
  "not"
  "only"
] @keyword.operator

(important) @keyword.modifier

; -------
; Pseudo-selectors and attribute selectors
; -------

(pseudo_element_selector (tag_name) @attribute)
(pseudo_class_selector (class_name) @attribute)
(attribute_name) @attribute

; -------
; Function calls: rgb(), var(), url(), calc(), ...
; -------

(function_name) @function.call

; -------
; Custom properties: --x where declared and where read
; -------

((property_name) @variable
  (#match? @variable "^--"))
((plain_value) @variable
  (#match? @variable "^--"))

; -------
; Constants: colours (with their leading #), id selectors, value keywords
; -------

(color_value "#" @constant)
(color_value) @constant
(id_name) @constant
(plain_value) @constant
(keyword_query) @constant
(keyframes_name) @constant

; -------
; Selectors
; -------

(namespace_name) @namespace

[
  (tag_name)
  (nesting_selector)
  (universal_selector)
] @tag

(class_name) @type

; -------
; Properties (declarations and media features)
; -------

[
  (property_name)
  (feature_name)
] @property

; -------
; At-rules and keyframe selectors
; -------

[
  "@media"
  "@charset"
  "@namespace"
  "@supports"
  "@keyframes"
  (at_keyword)
  (to)
  (from)
] @keyword

; -------
; Punctuation
; -------

[
  "{"
  "}"
  "("
  ")"
  "["
  "]"
] @punctuation.bracket

[
  "#"
  "."
  ","
  ":"
  "::"
  ";"
] @punctuation.delimiter

; -------
; Operators: combinators, attribute matchers, calc arithmetic
; -------

[
  "~"
  ">"
  "+"
  "-"
  "*"
  "/"
  "="
  "^="
  "|="
  "~="
  "$="
  "*="
] @operator
