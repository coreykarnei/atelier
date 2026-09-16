; JSX additions — combined BEFORE injections.scm and highlights.scm for the
; `jsx` language, so the names first mentioned here (tag, module, attribute,
; punctuation.bracket) outrank the parent's for the same ranges. Only names
; that should win inside JSX are introduced here; in particular this file
; must not mention @type or @variable first, or every capitalised identifier
; in the file would stop being a constant / decorator / constructor.

; <div> / <Component> / </div> / <br />
(jsx_opening_element
  (identifier) @tag)

(jsx_closing_element
  (identifier) @tag)

(jsx_self_closing_element
  (identifier) @tag)

; <My.Component>
(jsx_opening_element
  (member_expression
    (identifier) @module
    (property_identifier) @tag))

(jsx_closing_element
  (member_expression
    (identifier) @module
    (property_identifier) @tag))

(jsx_self_closing_element
  (member_expression
    (identifier) @module
    (property_identifier) @tag))

; <div className="x" onClick={f}>
(jsx_attribute
  (property_identifier) @attribute)

(jsx_opening_element
  [
    "<"
    ">"
  ] @punctuation.bracket)

(jsx_closing_element
  [
    "</"
    ">"
  ] @punctuation.bracket)

(jsx_self_closing_element
  [
    "<"
    "/>"
  ] @punctuation.bracket)
