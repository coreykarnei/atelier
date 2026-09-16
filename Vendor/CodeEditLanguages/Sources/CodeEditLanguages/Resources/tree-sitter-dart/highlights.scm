; Dart highlights — Atelier.
;
; Resolution is one capture per text range, and the winner is the capture
; NAME that first appears earliest in this file (tree-sitter numbers capture
; names by first appearance). So each name is introduced in priority order —
; specific names (builtins, declarations, members, calls) before the generic
; ones, and `variable` is introduced last of all, including its use inside
; string interpolation. Only #match?, #not-match?, #eq?, #not-eq? resolve.
;
; Bundled-grammar notes: no call_expression, labeled_statement, catch_parameter,
; extension_type_declaration or dot_shorthand nodes; `on` in a try is an
; anonymous child of try_statement, not of catch_clause.

; Comments
; --------------------
(documentation_comment) @comment.documentation
(comment) @comment

; Strings
; --------------------
(escape_sequence) @string.escape

(template_substitution
  "$" @punctuation.special
  "{" @punctuation.special
  "}" @punctuation.special)

(string_literal) @string

(symbol_literal) @string.special
(symbol_literal
  (identifier) @string.special)

; `library a.b.c;` / `part of a.b.c;` / `import '…' as alias;`
(dotted_identifier_list) @module
(dotted_identifier_list
  (identifier) @module)
(import_specification
  (identifier) @module)

; Literals
; --------------------
(decimal_floating_point_literal) @number.float

[
  (hex_integer_literal)
  (decimal_integer_literal)
] @number

(true) @boolean
(false) @boolean
(null_literal) @constant.builtin

; Keywords
; --------------------
[
  "import"
  "export"
  "library"
  "part"
  "show"
  "hide"
  "deferred"
  (part_of_builtin)
] @keyword.import

"return" @keyword.return

[
  "if"
  "else"
  "switch"
  "default"
  "when"
  (case_builtin)
] @keyword.conditional

[
  "for"
  "while"
  "do"
  "continue"
  (break_builtin)
] @keyword.repeat

; `on` is a superclass constraint in mixins/extensions and an exception
; filter in try — plain keyword first so it wins those two spots.
(mixin_declaration
  "on" @keyword)
(extension_declaration
  "on" @keyword)

[
  "try"
  "catch"
  "finally"
  "throw"
  (rethrow_builtin)
] @keyword.exception
(try_statement
  "on" @keyword.exception)

[
  "as"
  "in"
  "is"
  "new"
] @keyword.operator

[
  "async"
  "async*"
  "sync*"
  "await"
  "yield"
] @keyword.coroutine

[
  "class"
  "enum"
  "extension"
  "mixin"
  "typedef"
] @keyword.type

[
  "get"
  "set"
  "factory"
  "operator"
] @keyword.function

[
  "abstract"
  "base"
  "covariant"
  "external"
  "final"
  "interface"
  "late"
  "required"
  "sealed"
  "static"
  (const_builtin)
  (final_builtin)
] @keyword.modifier

(inferred_type) @keyword

[
  "extends"
  "implements"
  "with"
  (assert_builtin)
] @keyword

; Annotations
; --------------------
(annotation
  "@" @attribute
  name: (identifier) @attribute)

; Builtin types
; --------------------
((type_identifier) @type.builtin
  (#match? @type.builtin "^(int|double|num|String|bool|List|Set|Map|Iterable|Runes|Symbol|Object|Never|Future|Stream|FutureOr|Type|dynamic)$"))

(void_type) @type.builtin
"dynamic" @type.builtin
"Function" @type.builtin

; Declarations
; --------------------
(enum_constant
  name: (identifier) @constant)

(constructor_signature
  name: (identifier) @constructor)

(constant_constructor_signature
  (identifier) @constructor)

(factory_constructor_signature
  (identifier) @constructor)

(type_alias
  (type_identifier) @type.definition)

(class_definition
  name: (identifier) @type)

(enum_declaration
  name: (identifier) @type)

(mixin_declaration
  name: (identifier) @type)

(extension_declaration
  name: (identifier) @type)

(function_signature
  name: (identifier) @function)

(getter_signature
  (identifier) @function.method)

(setter_signature
  name: (identifier) @function.method)

; Parameters
; --------------------
(formal_parameter
  (identifier) @variable.parameter)

; parameters of a function type: `void Function(T value, {bool flag})`
(typed_identifier
  (identifier) @variable.parameter)

(named_argument
  (label
    (identifier) @variable.parameter))

(catch_clause
  (_
    (identifier) @variable.parameter))

; Labels (`break outer;` / `continue outer;` — the `outer:` site itself has
; no node in this grammar)
; --------------------
(break_statement
  (identifier) @label)

(continue_statement
  (identifier) @label)

; Calls
; --------------------
; The grammar has no call_expression node: a call is an identifier
; immediately followed by a selector whose first child is an argument_part.
(((identifier) @function.builtin
  (#match? @function.builtin "^(print|identical)$"))
  .
  (selector
    .
    (argument_part)))

; `..write('a')`
(cascade_section
  (cascade_selector
    (identifier) @function.method.call)
  .
  (argument_part))

; `..tags.add('y')` — inside a cascade the selector is a bare child
(cascade_section
  (unconditional_assignable_selector
    (identifier) @function.method.call)
  .
  (argument_part))

((selector
  (unconditional_assignable_selector
    (identifier) @function.method.call))
  .
  (selector
    (argument_part)))

(((identifier) @function.call
  (#match? @function.call "^_?[a-z]"))
  .
  (selector
    .
    (argument_part)))

; Members
; --------------------
; field declarations in a class body
(declaration
  (initialized_identifier_list
    (initialized_identifier
      (identifier) @variable.member)))

(declaration
  (static_final_declaration_list
    (static_final_declaration
      (identifier) @variable.member)))

; `this.x` initialising formals
(constructor_param
  (identifier) @variable.member)

(cascade_section
  (cascade_selector
    (identifier) @variable.member))

(unconditional_assignable_selector
  (identifier) @variable.member)

(conditional_assignable_selector
  (identifier) @variable.member)

; Types
; --------------------
(type_identifier) @type

(scoped_identifier
  scope: (identifier) @type)

((scoped_identifier
  scope: (identifier) @type
  name: (identifier) @type)
  (#match? @type "^[a-zA-Z]"))

; Capitalised identifiers in expression position: constructor calls,
; static member access (`Color.red`), type literals.
((identifier) @type
  (#match? @type "^_?[A-Z].*[a-z]"))

; Builtin variables
; --------------------
(this) @variable.builtin
(super) @variable.builtin

; Punctuation
; --------------------
(type_arguments
  "<" @punctuation.bracket
  ">" @punctuation.bracket)

(type_parameters
  "<" @punctuation.bracket
  ">" @punctuation.bracket)

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

[
  ";"
  "."
  ","
  "?."
] @punctuation.delimiter

; Operators
; --------------------
[
  "@"
  "=>"
  ".."
  "??"
  "=="
  "!"
  "?"
  ":"
  "&&"
  "%"
  "<"
  ">"
  "="
  ">="
  "<="
  "||"
  "~/"
  ">>>="
  ">>="
  "<<="
  "&="
  "|="
  "??="
  "%="
  "+="
  "-="
  "*="
  "/="
  "^="
  "~/="
  (shift_operator)
  (multiplicative_operator)
  (increment_operator)
  (is_operator)
  (prefix_operator)
  (equality_operator)
  (additive_operator)
] @operator

; Catch-all (`variable` is introduced here, last, on purpose)
; --------------------
(template_substitution
  "$" @punctuation.special
  (identifier_dollar_escaped) @variable)

(identifier) @variable
