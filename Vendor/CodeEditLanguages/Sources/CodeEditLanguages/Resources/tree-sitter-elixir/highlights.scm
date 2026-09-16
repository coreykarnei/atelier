; Elixir highlights — ported from nvim-treesitter / Helix / elixir-lang's
; tree-sitter-elixir queries and adapted to this editor's resolution rule:
; for one text range the capture whose *name* first appears earliest in this
; file wins. Sections are therefore ordered by priority, and helper captures
; are named with the bucket they sit inside (e.g. `@comment.documentation.name`)
; so a helper never paints a range plain.

; Documentation ---------------------------------------------------------------

(unary_operator
  operator: "@" @comment.documentation
  operand: (call
    target: (identifier) @comment.documentation.name
    (arguments
      [
        (string) @comment.documentation
        (charlist) @comment.documentation
        (sigil
          quoted_start: _ @comment.documentation
          quoted_end: _ @comment.documentation) @comment.documentation
        (boolean) @comment.documentation
      ]))
  (#match? @comment.documentation.name "^(moduledoc|typedoc|shortdoc|doc)$")) @comment.documentation

; Keywords --------------------------------------------------------------------

; * function / macro / guard definitions
(call
  target: (identifier) @keyword.function
  (#match? @keyword.function "^(def|defp|defmacro|defmacrop|defguard|defguardp|defdelegate|defn|defnp|defoverridable)$"))

; * module / protocol / struct declarations
(call
  target: (identifier) @keyword.type
  (#match? @keyword.type "^(defmodule|defprotocol|defimpl|defstruct|defexception)$"))

; * imports
(call
  target: (identifier) @keyword.import
  (#match? @keyword.import "^(alias|import|require|use)$"))

; * conditionals
(call
  target: (identifier) @keyword.conditional
  (#match? @keyword.conditional "^(if|unless|case|cond|with|else)$"))

"else" @keyword.conditional

; * loops
(call
  target: (identifier) @keyword.repeat
  (#match? @keyword.repeat "^for$"))

; * exceptions
(call
  target: (identifier) @keyword.exception
  (#match? @keyword.exception "^(try|raise|reraise|throw|catch|rescue)$"))

[
  "catch"
  "rescue"
] @keyword.exception

; * remaining kernel special forms
(call
  target: (identifier) @keyword
  (#match? @keyword "^(receive|quote|unquote|unquote_splicing|super)$"))

; * reserved words
[
  "when"
  "fn"
  "do"
  "end"
  "after"
] @keyword

; * word operators
[
  "and"
  "or"
  "not"
  "in"
  "not in"
] @keyword.operator

; Definitions -----------------------------------------------------------------

; * `def name(params) when guard`, `def name(params)`, `def name`
(call
  target: (identifier) @keyword.function.def
  (arguments
    [
      (identifier) @function
      (call
        target: (identifier) @function)
      (binary_operator
        left: [
          (identifier) @function
          (call
            target: (identifier) @function)
        ]
        operator: "when")
    ])
  (#match? @keyword.function.def "^(def|defp|defmacro|defmacrop|defguard|defguardp|defdelegate|defn|defnp)$"))

; * parameters of a definition head
(call
  target: (identifier) @keyword.function.def
  (arguments
    [
      (call
        (arguments
          [
            (identifier) @variable.parameter
            (binary_operator
              left: (identifier) @variable.parameter
              operator: "\\\\")
            (binary_operator
              operator: "="
              right: (identifier) @variable.parameter)
          ]))
      (binary_operator
        left: (call
          (arguments
            [
              (identifier) @variable.parameter
              (binary_operator
                left: (identifier) @variable.parameter
                operator: "\\\\")
              (binary_operator
                operator: "="
                right: (identifier) @variable.parameter)
            ]))
        operator: "when")
    ])
  (#match? @keyword.function.def "^(def|defp|defmacro|defmacrop|defguard|defguardp|defdelegate|defn|defnp)$"))

; * parameters of an anonymous function
(anonymous_function
  (stab_clause
    left: (arguments
      [
        (identifier) @variable.parameter
        (binary_operator
          operator: "="
          right: (identifier) @variable.parameter)
      ])))

; Constants -------------------------------------------------------------------

((identifier) @constant.builtin
  (#match? @constant.builtin "^(__MODULE__|__DIR__|__ENV__|__CALLER__|__STACKTRACE__)$"))

(nil) @constant.builtin

(boolean) @boolean

; Module attributes -----------------------------------------------------------

(unary_operator
  operator: "@" @attribute
  operand: [
    (identifier) @attribute
    (call
      target: (identifier) @attribute)
  ])

; Types -----------------------------------------------------------------------

; * struct literal `%Name{}`
(struct
  (alias) @type)

; * typespecs, left of `::`: `@spec f(a(), B.t()) ::`, `@type t ::`
(unary_operator
  operator: "@"
  operand: (call
    target: (identifier) @attribute.typespec
    (arguments
      (binary_operator
        left: [
          (identifier) @type
          (call
            target: (identifier) @function
            (arguments
              [
                (call
                  target: (identifier) @type)
                (call
                  target: (dot
                    right: (identifier) @type))
              ]))
        ]
        operator: "::")))
  (#match? @attribute.typespec "^(spec|type|typep|opaque|callback|macrocallback)$"))

; * typespecs, right of `::`: `:: r()`, `:: B.t()`
(unary_operator
  operator: "@"
  operand: (call
    target: (identifier) @attribute.typespec
    (arguments
      (binary_operator
        operator: "::"
        right: [
          (call
            target: (identifier) @type)
          (call
            target: (dot
              right: (identifier) @type))
        ])))
  (#match? @attribute.typespec "^(spec|type|typep|opaque|callback|macrocallback)$"))

; * bitstring segment types `<<x::binary-size(2)>>`
(bitstring
  (binary_operator
    operator: "::"
    right: [
      (identifier) @type.builtin
      (call
        target: (identifier) @type.builtin)
      (binary_operator
        left: (identifier) @type.builtin
        right: (call
          target: (identifier) @type.builtin))
    ]))

; Builtins --------------------------------------------------------------------

(call
  target: (identifier) @function.builtin
  (#match? @function.builtin "^(abs|apply|binary_part|binary_slice|binding|bit_size|byte_size|ceil|dbg|destructure|div|elem|exit|floor|function_exported\\?|get_and_update_in|get_in|hd|inspect|is_atom|is_binary|is_bitstring|is_boolean|is_exception|is_float|is_function|is_integer|is_list|is_map|is_map_key|is_nil|is_number|is_pid|is_port|is_reference|is_struct|is_tuple|length|macro_exported\\?|make_ref|map_size|match\\?|max|min|node|pop_in|put_elem|put_in|rem|round|self|send|spawn|spawn_link|spawn_monitor|struct|struct!|tl|to_charlist|to_string|trunc|tuple_size|update_in|var!)$"))

; Fields & calls --------------------------------------------------------------

; * field access without parentheses: `state.count`, `e.message`
(call
  target: (dot
    left: [
      (identifier)
      (call)
    ]
    right: (identifier) @variable.member)
  .)

; * local call
(call
  target: (identifier) @function.call)

; * remote call `Mod.fun(...)`, `:erlang.fun(...)`
(call
  target: (dot
    right: (identifier) @function.call))

; * pipe into a bare identifier
(binary_operator
  operator: "|>"
  right: (identifier) @function.call)

; * capture `&fun/1`, `&Mod.fun/2`
(unary_operator
  operator: "&"
  operand: (binary_operator
    left: [
      (identifier) @function.call
      (call
        target: (dot
          right: (identifier) @function.call))
    ]
    operator: "/"
    right: (integer) @operator))

; Modules ---------------------------------------------------------------------

(alias) @module

(call
  target: (dot
    left: (atom) @module))

; Operators -------------------------------------------------------------------

; * capture placeholder `&1`
(unary_operator
  operator: "&"
  operand: (integer) @operator)

(operator_identifier) @operator

(unary_operator
  operator: _ @operator)

(binary_operator
  operator: _ @operator)

(dot
  operator: _ @operator)

(stab_clause
  operator: _ @operator)

"%" @punctuation.special

(interpolation
  "#{" @punctuation.special
  "}" @punctuation.special)

; Literals --------------------------------------------------------------------

(integer) @number

(float) @number.float

(char) @character

; * regex sigil
(sigil
  (sigil_name) @string.regex.name
  quoted_start: _ @string.regex
  quoted_end: _ @string.regex
  (#match? @string.regex.name "^[rR]$")) @string.regex

(escape_sequence) @string.escape

; * string sigil
(sigil
  (sigil_name) @string.name
  quoted_start: _ @string
  quoted_end: _ @string
  (#match? @string.name "^[sS]$")) @string

[
  (string)
  (charlist)
] @string

; * every other sigil
(sigil
  (sigil_name) @string.special.name
  quoted_start: _ @string.special
  quoted_end: _ @string.special
  (#not-match? @string.special.name "^[sSrR]$")) @string.special

; * atoms and keyword-list keys
[
  (atom)
  (quoted_atom)
  (keyword)
  (quoted_keyword)
] @constant

; Comments --------------------------------------------------------------------

(comment) @comment

; * unused identifiers `_x`
((identifier) @comment.unused
  (#match? @comment.unused "^_"))

; Identifiers -----------------------------------------------------------------

; * `def name |> other` (piped definition body; the right side is a value)
(call
  target: (identifier) @keyword.function.def
  (arguments
    (binary_operator
      operator: "|>"
      right: (identifier) @variable))
  (#match? @keyword.function.def "^(def|defp|defmacro|defmacrop|defguard|defguardp|defdelegate|defn|defnp)$"))

(identifier) @variable

; Punctuation -----------------------------------------------------------------

[
  ","
  ";"
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "<<"
  ">>"
] @punctuation.bracket
