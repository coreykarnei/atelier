; YAML highlights — Atelier revision.
;
; The editor keeps one capture per range, and the winner is the capture whose
; NAME is mentioned first in this file (see Scripts/hlcheck/README.md,
; "Precedence is by capture *name*"). Pattern order is irrelevant; this file
; is laid out so names appear in priority order:
;
;   comment · string.escape · boolean · number · number.float ·
;   constant.builtin · type · label · attribute · keyword.operator ·
;   variable.member · punctuation.special · punctuation.delimiter ·
;   punctuation.bracket · string
;
; Structure carries the colour — keys, literals, tags, anchors, markers.
; Plain and quoted string VALUES land in the string bucket as prose; they
; are never painted as code buckets. Ported from nvim-treesitter / Helix;
; only #match? / #eq? / #not-match? / #not-eq? predicates resolve here.

; -------
; Comments
; -------

(comment) @comment

; -------
; Literals
; -------

(escape_sequence) @string.escape

(boolean_scalar) @boolean

; YAML 1.1 booleans the 1.2 grammar reads as plain strings — only in value
; position (a key named `yes:` stays a key). Kept to yes/no; `on`/`off` and
; the Norway problem (`no` as a country code) are why this list is short.
(block_mapping_pair
  value: (flow_node
    (plain_scalar
      (string_scalar) @boolean
      (#match? @boolean "^(yes|no|Yes|No|YES|NO)$"))))
(block_sequence_item
  (flow_node
    (plain_scalar
      (string_scalar) @boolean
      (#match? @boolean "^(yes|no|Yes|No|YES|NO)$"))))
(flow_sequence
  (flow_node
    (plain_scalar
      (string_scalar) @boolean
      (#match? @boolean "^(yes|no|Yes|No|YES|NO)$"))))
(flow_pair
  value: (flow_node
    (plain_scalar
      (string_scalar) @boolean
      (#match? @boolean "^(yes|no|Yes|No|YES|NO)$"))))

(integer_scalar) @number
(float_scalar) @number.float

(null_scalar) @constant.builtin

; -------
; Tags, anchors, aliases, directives
; -------

(tag) @type

[
  (anchor_name)
  (alias_name)
] @label

[
  (yaml_directive)
  (tag_directive)
  (reserved_directive)
] @attribute

; -------
; The merge key `<<: *base`
; -------

(block_mapping_pair
  key: (flow_node
    (plain_scalar
      (string_scalar) @keyword.operator
      (#eq? @keyword.operator "<<"))))
(flow_pair
  key: (flow_node
    (plain_scalar
      (string_scalar) @keyword.operator
      (#eq? @keyword.operator "<<"))))

; -------
; Mapping keys
; -------

(block_mapping_pair
  key: (flow_node
    [
      (double_quote_scalar)
      (single_quote_scalar)
    ] @variable.member))

(block_mapping_pair
  key: (flow_node
    (plain_scalar
      (string_scalar) @variable.member)))

(flow_mapping
  (_
    key: (flow_node
      [
        (double_quote_scalar)
        (single_quote_scalar)
      ] @variable.member)))

(flow_mapping
  (_
    key: (flow_node
      (plain_scalar
        (string_scalar) @variable.member))))

; -------
; Punctuation
; -------

; Document markers, anchor/alias sigils, block scalar indicators
[
  "---"
  "..."
  "&"
  "*"
  "|"
  ">"
] @punctuation.special

; Sequence dashes, key/value colons, flow commas, complex-key `?`
[
  "-"
  ":"
  ","
  "?"
] @punctuation.delimiter

[
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; -------
; String values (prose) — last, so every structural capture above wins
; -------

[
  (double_quote_scalar)
  (single_quote_scalar)
  (block_scalar)
  (string_scalar)
] @string
