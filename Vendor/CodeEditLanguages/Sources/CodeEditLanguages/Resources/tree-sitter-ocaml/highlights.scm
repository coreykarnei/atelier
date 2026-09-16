; OCaml highlights — ported from nvim-treesitter / Helix and tuned for
; Atelier's editor, which resolves one capture per range by the *capture
; name's index*: the name that first appears earliest in this file wins any
; range it shares with a later-named capture. Sections are therefore ordered
; specific → generic (builtins before functions before variables, keyword
; buckets before the bare keyword bucket, keywords before operators, and the
; (value_name) catch-all last). Only #match? / #not-match? / #eq? / #not-eq?
; resolve here, and every capture — even a predicate helper — is painted, so
; there are no `@_helper` captures. This file also serves `.mli`
; (tree-sitter-ocaml-interface), so every node named here must exist in both
; bundled grammars.

; Comments
;---------

((comment) @comment.documentation
  (#match? @comment.documentation "^\\(\\*\\*[^*)]"))

[(comment) (line_number_directive) (directive) (shebang)] @comment

; Strings, characters, numbers
;------------------------------

[(conversion_specification) (pretty_printing_indication)] @string.special

(escape_sequence) @string.escape

(character) @character

(string) @string

(quoted_string "{" @string "}" @string) @string

((number) @number.float
  (#match? @number.float "^([0-9][0-9_]*(\\.|[eE])|0[xX][0-9a-fA-F_]*(\\.|[pP]))"))

[(number) (signed_number)] @number

(boolean) @boolean

; `()` — the unit value, not two brackets.
(unit ["(" ")"] @constant.builtin)

; Word operators
;---------------

((value_name) @keyword.operator
  (#eq? @keyword.operator "not"))

((mult_operator) @keyword.operator
  (#match? @keyword.operator "^(mod|land|lor|lxor)$"))

((pow_operator) @keyword.operator
  (#match? @keyword.operator "^(lsl|lsr|asr)$"))

((or_operator) @keyword.operator
  (#eq? @keyword.operator "or"))

"new" @keyword.operator

; Builtins
;---------

((value_pattern) @variable.builtin
  (#eq? @variable.builtin "self"))

((value_name) @variable.builtin
  (#match? @variable.builtin "^(self|stdin|stdout|stderr)$"))

((value_name) @function.builtin
  (#match? @function.builtin "^(raise(_notrace)?|failwith|invalid_arg|ignore|ref|incr|decr|fst|snd|succ|pred|abs|abs_float|min|max|compare|exit|at_exit|float|float_of_int|int_of_float|truncate|float_of_string(_opt)?|int_of_string(_opt)?|bool_of_string(_opt)?|string_of_int|string_of_float|string_of_bool|char_of_int|int_of_char|sqrt|exp|log|log10|sin|cos|tan|floor|ceil|print_(string|int|float|char|endline|newline|bytes)|prerr_(string|int|float|char|endline|newline|bytes)|printf|eprintf|sprintf|fprintf|read_line|read_int(_opt)?|read_float(_opt)?|open_in|open_out|close_in|close_out|input_line|output_string|flush|flush_all|format_of_string|string_of_format)$"))

; Keywords
;---------
; Before Functions/Operators: `with` is bucketed by parent, and the
; let/match operators (`let*`, `match+`) read as keywords inside their
; definitions — `keyword` must outrank `operator`.

["fun" "function" "functor" "method"] @keyword.function

["if" "then" "else" "match" "when"] @keyword.conditional
(match_expression "with" @keyword.conditional)

["for" "to" "downto" "while" "do" "done"] @keyword.repeat

["exception" "try"] @keyword.exception
(try_expression "with" @keyword.exception)

["include" "open"] @keyword.import

["type" "class" "object" "struct" "sig"] @keyword.type

["lazy" "mutable" "nonrec" "rec" "private" "virtual"] @keyword.modifier

[
  "and" "as" "assert" "begin" "constraint" "end" "external" "in" "inherit"
  "initializer" "let" "module" "of" "val" "with"
] @keyword

(match_expression (match_operator) @keyword)

(value_definition [(let_operator) (let_and_operator)] @keyword)

; Functions
;----------

(method_name) @function.method

(let_binding
  pattern: (value_name) @function
  (parameter))

(let_binding
  pattern: (value_name) @function
  body: [(fun_expression) (function_expression)])

; `val f : a -> b` is a function; `val pi : float` stays a variable.
(value_specification (value_name) @function (function_type))

(external (value_name) @function)

(infix_expression
  left: (value_path (value_name) @function.call)
  operator: (concat_operator) @operator
  (#eq? @operator "@@"))

(infix_expression
  operator: (rel_operator) @operator
  right: (value_path (value_name) @function.call)
  (#eq? @operator "|>"))

(application_expression
  function: (value_path (value_name) @function.call))

; Parameters
;-----------

(value_pattern) @variable.parameter

; Types
;------

((type_constructor) @type.builtin
  (#match? @type.builtin "^(int|char|bytes|string|float|bool|unit|exn|array|list|option|result|ref|int32|int64|nativeint|format|format4|format6|lazy_t|in_channel|out_channel)$"))

[(constructor_name) (tag)] @constructor

; Fields & labels
;----------------

[(field_name) (instance_variable_name)] @variable.member

(label_name) @label

; Modules
;--------

[(module_name) (module_type_name)] @module

[(class_name) (class_type_name) (type_constructor) (type_variable)] @type

; Variables (catch-all — after every more specific (value_name) use)
;----------

(value_name) @variable

; Operators
;----------

[
  (prefix_operator)
  (sign_operator)
  (pow_operator)
  (mult_operator)
  (add_operator)
  (concat_operator)
  (rel_operator)
  (and_operator)
  (or_operator)
  (assign_operator)
  (hash_operator)
  (indexing_operator)
  (let_operator)
  (let_and_operator)
  (match_operator)
] @operator

["*" "#" "::" "<-" "->"] @operator

; Punctuation
;------------

(attribute ["[@" "]"] @punctuation.special)
(item_attribute ["[@@" "]"] @punctuation.special)
(floating_attribute ["[@@@" "]"] @punctuation.special)
(extension ["[%" "]"] @punctuation.special)
(item_extension ["[%%" "]"] @punctuation.special)
(quoted_extension ["{%" "}"] @punctuation.special)
(quoted_item_extension ["{%%" "}"] @punctuation.special)

"%" @punctuation.special

["(" ")" "[" "]" "{" "}" "[|" "|]" "[<" "[>"] @punctuation.bracket

(object_type ["<" ">"] @punctuation.bracket)

[
  "," "." ";" ":" "=" "|" "~" "?" "+" "-" "!" ">" "&"
  ";;" ":>" "+=" ":=" ".."
] @punctuation.delimiter

; Attributes & extensions
;------------------------

(attribute_id) @attribute
