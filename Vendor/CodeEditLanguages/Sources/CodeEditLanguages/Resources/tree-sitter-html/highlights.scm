; HTML highlights — Atelier.
;
; Combined AFTER tree-sitter-html/injections.scm (so `injection.content` is
; the first-numbered name; leave that file alone — script/style still inject
; javascript/css through it). The editor keeps the capture with the lowest
; index per range, and tree-sitter numbers capture NAMES by first mention in
; the combined text — so the order names first appear below is the priority
; order: comment, doctype constant, tag before attribute, entities before
; plain strings, headings before brackets and the `=` delimiter.
; Text content is deliberately left unpainted (prose reads as prose); only the
; inner text of <title> and <h1>…<h6> carries a markup.heading bucket.
; Ported from nvim-treesitter's html/html_tags queries and Helix's html query,
; reduced to the predicates this editor resolves (#match? #eq? and negations)
; and the captures it can place.

; Comments
;---------

(comment) @comment

; Doctype — `<!DOCTYPE html>` as one constant (the bundled grammar hides the
; DOCTYPE word itself; nvim's inner `(doctype)` alias isn't exposed here).
; Its `<!` and `>` are painted as brackets below.
;------------------------------------------------------------------------

(doctype) @constant

; Tags
;-----

(tag_name) @tag

(erroneous_end_tag_name) @tag

; Attributes
;-----------

(attribute_name) @attribute

; Entities — `&amp;` `&#8212;` `&#x2318;`
;--------------------------------------

(entity) @string.escape

; Attribute values — quoted (quotes included) or bare. href/src URLs are
; strings too (the goal folds string.special.url into string).
;-------------------------------------------------------------------------

(attribute
  [
    (attribute_value)
    (quoted_attribute_value)
  ] @string)

; Headings — inner text of <title> and <h1>…<h6>
;-----------------------------------------------

((element
  (start_tag
    (tag_name) @tag)
  (text) @markup.heading)
  (#eq? @tag "title"))

((element
  (start_tag
    (tag_name) @tag)
  (text) @markup.heading.1)
  (#eq? @tag "h1"))

((element
  (start_tag
    (tag_name) @tag)
  (text) @markup.heading.2)
  (#eq? @tag "h2"))

((element
  (start_tag
    (tag_name) @tag)
  (text) @markup.heading.3)
  (#eq? @tag "h3"))

((element
  (start_tag
    (tag_name) @tag)
  (text) @markup.heading.4)
  (#eq? @tag "h4"))

((element
  (start_tag
    (tag_name) @tag)
  (text) @markup.heading.5)
  (#eq? @tag "h5"))

((element
  (start_tag
    (tag_name) @tag)
  (text) @markup.heading.6)
  (#eq? @tag "h6"))

; Punctuation
;------------

[
  "<"
  ">"
  "</"
  "/>"
  "<!"
] @punctuation.bracket

"=" @punctuation.delimiter
