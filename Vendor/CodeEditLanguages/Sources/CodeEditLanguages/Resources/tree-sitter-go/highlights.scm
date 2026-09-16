; Go highlights — ported from nvim-treesitter / Helix for Atelier's editor.
;
; Resolution rule: for one text range the capture that appears EARLIEST in
; this file wins, so specific patterns come first and the identifier
; catch-all comes last. Only #match? / #not-match? / #eq? / #not-eq?
; predicates resolve here.

; ---------------------------------------------------------------- Doc comments
; Comments that open the file, or lead directly into a declaration. The
; shape `(comment) @doc . (comment)* . (decl)` is deliberate: an anchor
; placed after a *captured* quantifier (`(comment)+ @doc .`) never matched
; top-level declarations in the bundled runtime, and this form gives every
; comment of a multi-line run its own match anyway.
(source_file
  .
  (comment)+ @comment.documentation)

(source_file
  (comment) @comment.documentation
  .
  (comment)*
  .
  [
    (package_clause)
    (const_declaration)
    (var_declaration)
    (type_declaration)
    (function_declaration)
    (method_declaration)
  ])

; Doc comments on grouped specs:  const ( // Foo is …\n Foo = 1 )
(const_declaration
  (comment) @comment.documentation
  .
  (comment)*
  .
  (const_spec))

(var_declaration
  (comment) @comment.documentation
  .
  (comment)*
  .
  (var_spec))

(type_declaration
  (comment) @comment.documentation
  .
  (comment)*
  .
  (type_spec))

(comment) @comment

; ------------------------------------------------------------------- Constants
(const_spec
  name: (identifier) @constant)

; -------------------------------------------------------------------- Builtins
(call_expression
  function: (identifier) @function.builtin
  (#match? @function.builtin "^(append|cap|clear|close|complex|copy|delete|imag|len|make|max|min|new|panic|print|println|real|recover)$"))

((identifier) @function.builtin
  (#match? @function.builtin "^(append|cap|clear|close|complex|copy|delete|imag|len|make|max|min|new|panic|print|println|real|recover)$"))

((type_identifier) @type.builtin
  (#match? @type.builtin "^(any|bool|byte|comparable|complex128|complex64|error|float32|float64|int|int16|int32|int64|int8|rune|string|uint|uint16|uint32|uint64|uint8|uintptr)$"))

[
  "chan"
  "map"
] @type.builtin

; ---------------------------------------------------------------- Constructors
; Go has no constructor syntax; `NewFoo(...)` / `MakeFoo(...)` is the idiom.
((call_expression
  function: (identifier) @constructor)
  (#match? @constructor "^[nN]ew.+$"))

((call_expression
  function: (identifier) @constructor)
  (#match? @constructor "^[mM]ake.+$"))

((call_expression
  function: (selector_expression
    field: (field_identifier) @constructor))
  (#match? @constructor "^[nN]ew.+$"))

; -------------------------------------------------------------- Function calls
(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (selector_expression
    field: (field_identifier) @function.method.call))

(call_expression
  function: (parenthesized_expression
    (identifier) @function.call))

; -------------------------------------------------------- Function definitions
(function_declaration
  name: (identifier) @function)

(method_declaration
  name: (field_identifier) @function.method)

(method_spec
  name: (field_identifier) @function.method)

; ----------------------------------------------------------------------- Types
(type_spec
  name: (type_identifier) @type.definition)

(type_alias
  name: (type_identifier) @type.definition)

(type_identifier) @type

; ------------------------------------------------------------------ Namespaces
(package_identifier) @module

(import_spec
  name: (dot) @module)

; ------------------------------------------------------------------ Parameters
; Generic type parameters (`[K comparable, V any]`) parse as parameter
; declarations in the bundled grammar; name them as types, not parameters.
(type_parameter_list
  (parameter_declaration
    name: (identifier) @type))

(parameter_declaration
  name: (identifier) @variable.parameter)

(variadic_parameter_declaration
  name: (identifier) @variable.parameter)

; ---------------------------------------------------------------------- Fields
(field_declaration
  name: (field_identifier) @variable.member)

(keyed_element
  .
  (literal_element
    (identifier) @variable.member))

(field_identifier) @variable.member

; ---------------------------------------------------------------------- Labels
(label_name) @label

(labeled_statement
  label: (label_name) @label)

; ------------------------------------------------------------------- Variables
(blank_identifier) @variable

(identifier) @variable

; ----------------------------------------------------------------- Regex calls
; Placed after the identifier catch-all so the helper captures (@_pkg, @_fn)
; never win a range — earlier patterns already own them. Only the first
; argument's literal is claimed here, ahead of the generic string patterns.
((call_expression
  function: (selector_expression
    operand: (identifier) @_pkg
    field: (field_identifier) @_fn)
  arguments: (argument_list
    .
    [
      (raw_string_literal)
      (interpreted_string_literal)
    ] @string.regex))
  (#eq? @_pkg "regexp")
  (#match? @_fn "^(Match|MatchReader|MatchString|Compile|CompilePOSIX|MustCompile|MustCompilePOSIX)$"))

; ------------------------------------------------------------------- Operators
[
  "--"
  "-"
  "-="
  ":="
  "!"
  "!="
  "..."
  "*"
  "*="
  "/"
  "/="
  "&"
  "&&"
  "&="
  "&^"
  "&^="
  "%"
  "%="
  "^"
  "^="
  "+"
  "++"
  "+="
  "<-"
  "<"
  "<<"
  "<<="
  "<="
  "="
  "=="
  ">"
  ">="
  ">>"
  ">>="
  "|"
  "|="
  "||"
  "~"
] @operator

; -------------------------------------------------------------------- Keywords
"func" @keyword.function

"return" @keyword.return

[
  "import"
  "package"
] @keyword.import

[
  "if"
  "else"
  "switch"
  "select"
  "case"
] @keyword.conditional

[
  "for"
  "range"
] @keyword.repeat

[
  "type"
  "struct"
  "interface"
] @keyword.type

[
  "var"
  "const"
] @keyword.storage

"go" @keyword.coroutine

[
  "break"
  "continue"
  "default"
  "defer"
  "fallthrough"
  "goto"
] @keyword

; ----------------------------------------------------------------- Punctuation
[
  "."
  ","
  ":"
  ";"
] @punctuation.delimiter

[
  "("
  ")"
  "{"
  "}"
  "["
  "]"
] @punctuation.bracket

; -------------------------------------------------------------------- Literals
[
  (interpreted_string_literal)
  (raw_string_literal)
] @string

(rune_literal) @character

(escape_sequence) @string.escape

(int_literal) @number

(float_literal) @number.float

(imaginary_literal) @number

[
  (true)
  (false)
] @boolean

[
  (nil)
  (iota)
] @constant.builtin
