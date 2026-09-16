; Java highlights — ported from nvim-treesitter (bucket names) for the
; CodeEditSourceEditor rule "one capture per range, lowest capture index
; wins". That index is the capture NAME's first appearance in this file, not
; the pattern's position — so a name introduced earlier beats one introduced
; later wherever two patterns tag the same node. Hence: @type.builtin before
; @type (so `var` stays builtin), @constructor before @type, every specific
; bucket before the (identifier) @variable catch-all at the very end.
; Only #match?/#eq? predicates resolve here (no #lua-match?/#any-of?).

; Constants — first, so SCREAMING_CASE beats field/member/module buckets.

((identifier) @constant
  (#match? @constant "^_*[A-Z][A-Z\\d_]+$"))

(enum_constant
  name: (identifier) @constant)

; Methods

(method_declaration
  name: (identifier) @function.method)

(method_invocation
  name: (identifier) @function.method.call)

(method_reference
  (identifier) @function.method.call .)

; `import static a.b.Util.helper;` — a lowercase last segment is a method
; (an uppercase one reads as a constant/type through the rules above/below).
((import_declaration
  "static"
  (scoped_identifier
    name: (identifier) @function.method.call))
  (#match? @function.method.call "^[a-z]"))

(super) @variable.builtin

; Constructors

(constructor_declaration
  name: (identifier) @constructor)

(compact_constructor_declaration
  name: (identifier) @constructor)

(object_creation_expression
  type: (type_identifier) @constructor)

(object_creation_expression
  type: (generic_type
    (type_identifier) @constructor))

; Parameters

(formal_parameter
  name: (identifier) @variable.parameter)

(spread_parameter
  (variable_declarator
    name: (identifier) @variable.parameter))

(inferred_parameters
  (identifier) @variable.parameter)

(lambda_expression
  parameters: (identifier) @variable.parameter)

(catch_formal_parameter
  name: (identifier) @variable.parameter)

; Labels

(labeled_statement
  (identifier) @label)

(break_statement
  (identifier) @label)

(continue_statement
  (identifier) @label)

; Annotations

(annotation
  "@" @attribute
  name: (identifier) @attribute)

(marker_annotation
  "@" @attribute
  name: (identifier) @attribute)

(annotation
  name: (scoped_identifier
    name: (identifier) @attribute))

(marker_annotation
  name: (scoped_identifier
    name: (identifier) @attribute))

(element_value_pair
  key: (identifier) @variable.member)

(annotation_type_element_declaration
  name: (identifier) @function.method)

; Types — builtins first so their name outranks @type on `var`.

[
  (boolean_type)
  (integral_type)
  (floating_point_type)
  (void_type)
] @type.builtin

((type_identifier) @type.builtin
  (#eq? @type.builtin "var"))

(type_arguments
  (wildcard "?" @type.builtin))

(interface_declaration
  name: (identifier) @type)

(annotation_type_declaration
  name: (identifier) @type)

(class_declaration
  name: (identifier) @type)

(record_declaration
  name: (identifier) @type)

(enum_declaration
  name: (identifier) @type)

(type_parameter
  (type_identifier) @type)

(type_identifier) @type

; `import java.util.List;` — the imported class reads as a type, the path as
; a module (below).
((import_declaration
  (scoped_identifier
    name: (identifier) @type))
  (#match? @type "^[A-Z]"))

(record_pattern
  . (identifier) @type)

((method_invocation
  object: (identifier) @type)
  (#match? @type "^[A-Z]"))

((method_reference
  . (identifier) @type)
  (#match? @type "^[A-Z]"))

((field_access
  object: (identifier) @type)
  (#match? @type "^[A-Z]"))

((scoped_identifier
  (identifier) @type)
  (#match? @type "^[A-Z]"))

; Namespaces — tag the path's leaf identifiers, not the enclosing
; scoped_identifier: the editor paints every captured range, so a wide
; @module under narrow @variable leaves would still render as variables.
; scoped_identifier only occurs in package/import/module directives and
; annotation names (expressions are field_access, types are
; scoped_type_identifier), so the bare form is safe.

(package_declaration
  (identifier) @module)

(import_declaration
  (identifier) @module)

(scoped_identifier
  (identifier) @module)

(import_declaration
  (asterisk
    "*" @punctuation.special))

; Fields

(field_declaration
  declarator: (variable_declarator
    name: (identifier) @variable.member))

(field_access
  field: (identifier) @variable.member)

(this) @variable.builtin

; Literals

(string_literal) @string

(escape_sequence) @string.escape

(character_literal) @character

[
  (hex_integer_literal)
  (decimal_integer_literal)
  (octal_integer_literal)
  (binary_integer_literal)
] @number

[
  (decimal_floating_point_literal)
  (hex_floating_point_literal)
] @number.float

[
  (true)
  (false)
] @boolean

(null_literal) @constant.builtin

; Comments

((block_comment) @comment.documentation
  (#match? @comment.documentation "^/\\*\\*[^*]"))

((line_comment) @comment.documentation
  (#match? @comment.documentation "^///([^/]|$)"))

[
  (line_comment)
  (block_comment)
] @comment

; Keywords

[
  "record"
  "class"
  "enum"
  "interface"
  "@interface"
] @keyword.type

[
  "abstract"
  "final"
  "native"
  "non-sealed"
  "open"
  "private"
  "protected"
  "public"
  "sealed"
  "static"
  "strictfp"
  "transitive"
  "transient"
  "volatile"
] @keyword.modifier

(modifiers
  "synchronized" @keyword.modifier)

(synchronized_statement
  "synchronized" @keyword)

[
  "return"
  "yield"
] @keyword.return

[
  "new"
  "instanceof"
] @keyword.operator

[
  "if"
  "else"
  "switch"
  "case"
  "when"
] @keyword.conditional

[
  "for"
  "while"
  "do"
  "continue"
  "break"
] @keyword.repeat

[
  "exports"
  "import"
  "module"
  "opens"
  "package"
  "provides"
  "requires"
  "uses"
] @keyword.import

[
  "throw"
  "throws"
  "finally"
  "try"
  "catch"
] @keyword.exception

[
  "assert"
  "default"
  "extends"
  "implements"
  "permits"
  "to"
  "with"
] @keyword

; Operators

; Generic angle brackets first, so they beat the < > operators below.
(type_arguments
  [
    "<"
    ">"
  ] @punctuation.bracket)

(type_parameters
  [
    "<"
    ">"
  ] @punctuation.bracket)

(ternary_expression
  [
    "?"
    ":"
  ] @keyword.conditional)

[
  "+"
  ":"
  "++"
  "-"
  "--"
  "&"
  "&&"
  "|"
  "||"
  "!"
  "!="
  "=="
  "*"
  "/"
  "%"
  "<"
  "<="
  ">"
  ">="
  "="
  "-="
  "+="
  "*="
  "/="
  "%="
  "->"
  "^"
  "^="
  "&="
  "|="
  "~"
  ">>"
  ">>>"
  "<<"
  "<<="
  ">>="
  ">>>="
  "::"
] @operator

; Punctuation

[
  ";"
  "."
  "..."
  ","
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Variables (catch-all — must stay last)

(identifier) @variable
