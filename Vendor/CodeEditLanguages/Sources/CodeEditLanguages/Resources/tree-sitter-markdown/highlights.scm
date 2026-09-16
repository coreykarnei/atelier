; Atelier: markdown block grammar → the editor's markup captures
; (CaptureName.markup*), ported from nvim-treesitter / Helix. Resolution is
; earliest-pattern-wins per exact range, and in the editor an enclosing range
; beats the runs nested inside it — so a heading is captured whole (marker +
; text, one colour, bold) while a fenced block is captured by its parts
; (fences, language label, content) so the label keeps its own colour and an
; injected body keeps its own language's highlighting.

; Headings — the whole line, marker included.
(atx_heading (atx_h1_marker)) @markup.heading.1
(atx_heading (atx_h2_marker)) @markup.heading.2
(atx_heading (atx_h3_marker)) @markup.heading.3
(atx_heading (atx_h4_marker)) @markup.heading.4
(atx_heading (atx_h5_marker)) @markup.heading.5
(atx_heading (atx_h6_marker)) @markup.heading.6
(setext_heading (setext_h1_underline)) @markup.heading.1
(setext_heading (setext_h2_underline)) @markup.heading.2

; Markers on their own (the harness sees these; the editor paints the
; enclosing heading range and drops them).
[
  (atx_h1_marker)
  (setext_h1_underline)
] @markup.heading.1

[
  (atx_h2_marker)
  (atx_h3_marker)
  (atx_h4_marker)
  (atx_h5_marker)
  (atx_h6_marker)
  (setext_h2_underline)
] @markup.heading

; Code blocks — by part, not as a whole (see header comment).
(fenced_code_block_delimiter) @markup.raw.block
(info_string (language) @label)
(code_fence_content) @markup.raw.block
(indented_code_block) @markup.raw.block

; Link reference definitions: [label]: <url> "title"
(link_label) @markup.link.label
(link_destination) @markup.link.url
(link_title) @string

; Lists and task boxes
[
  (list_marker_plus)
  (list_marker_minus)
  (list_marker_star)
  (list_marker_dot)
  (list_marker_parenthesis)
] @markup.list

(task_list_marker_checked) @markup.list.checked
(task_list_marker_unchecked) @markup.list.unchecked

; Block quotes — the whole quote, text included (its inlines are not
; injected, so the block layer owns them).
(block_quote) @markup.quote
(block_quote_marker) @punctuation.special

; Tables — header cells read as headings, rules and pipes as punctuation.
(pipe_table_header (pipe_table_cell) @markup.heading)
(pipe_table_delimiter_row) @punctuation.special
(pipe_table_delimiter_cell) @punctuation.special
(pipe_table_header "|" @punctuation.special)
(pipe_table_row "|" @punctuation.special)
(pipe_table_delimiter_row "|" @punctuation.special)

(thematic_break) @punctuation.special
(block_continuation) @punctuation.special
(backslash_escape) @string.escape
