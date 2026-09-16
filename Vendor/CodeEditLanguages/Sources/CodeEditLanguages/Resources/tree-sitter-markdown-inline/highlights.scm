; Atelier: markdown inline grammar → the editor's markup captures
; (CaptureName.markup*), ported from nvim-treesitter / Helix. In the editor
; an enclosing range beats the runs nested inside it, so `*emphasis*`,
; `**strong**`, `~~struck~~` and `` `code` `` are captured whole (delimiters
; included) and read as one styled run.
(code_span) @markup.raw
(emphasis) @markup.italic
(strong_emphasis) @markup.strong
(strikethrough) @markup.strikethrough

; Links and images: text/labels blue, destinations teal, titles as strings.
[
  (link_text)
  (link_label)
  (image_description)
] @markup.link.label

[
  (link_destination)
  (uri_autolink)
  (email_autolink)
] @markup.link.url

(link_title) @string

(inline_link ["[" "]" "(" ")"] @punctuation.bracket)
(image ["!" "[" "]" "(" ")"] @punctuation.bracket)
(full_reference_link ["[" "]"] @punctuation.bracket)
(collapsed_reference_link ["[" "]"] @punctuation.bracket)
(shortcut_link ["[" "]"] @punctuation.bracket)

; Escapes, hard breaks, entities
[
  (backslash_escape)
  (hard_line_break)
  (entity_reference)
  (numeric_character_reference)
] @string.escape

; Delimiters (the harness sees these; the editor paints the enclosing span).
[
  (emphasis_delimiter)
  (code_span_delimiter)
] @punctuation.delimiter
