; PHP highlights — ported from nvim-treesitter's php_only query for the
; grammar bundled in CodeLanguages-Container (a PHP 8.0-era build: it has
; attribute_list / enum_case / match / property_promotion_parameter, but no
; namespace_use_clause, string_content, relative_name, exit_statement or
; class_constant_declaration; `use Foo\Bar` is a bare qualified_name).
;
; Resolution: for one text range the capture whose *name* first appears
; earliest in this file wins, so names are introduced in priority order —
; specific (builtins, constructors, members, keyword buckets) before generic
; (type, variable, punctuation). A field name only has to exist somewhere in
; the grammar to compile, so patterns are written field-free where the
; bundled grammar's shape is uncertain.

; Tags

(php_tag) @tag
"?>" @tag

; Comments

((comment) @comment.documentation
  (#match? @comment.documentation "^/\\*\\*"))
(comment) @comment

; Attributes

"#[" @punctuation.special
(attribute (name) @attribute)
(attribute (qualified_name (name) @attribute))

; Keywords

[
  "and"
  "as"
  "instanceof"
  "or"
  "xor"
  "new"
  "clone"
] @keyword.operator

[
  "fn"
  "function"
] @keyword.function

[
  "enum"
  "class"
  "interface"
  "trait"
] @keyword.type

[
  "abstract"
  "const"
  "final"
  "private"
  "protected"
  "public"
  "readonly"
  (static_modifier)
  (var_modifier)
] @keyword.modifier

(function_static_declaration
  "static" @keyword.modifier)

[
  "return"
  "yield"
] @keyword.return

(yield_expression
  "from" @keyword.return)

[
  "case"
  "default"
  "else"
  "elseif"
  "endif"
  "endswitch"
  "if"
  "switch"
  "match"
] @keyword.conditional

[
  "break"
  "continue"
  "do"
  "endfor"
  "endforeach"
  "endwhile"
  "for"
  "foreach"
  "while"
] @keyword.repeat

[
  "catch"
  "finally"
  "throw"
  "try"
] @keyword.exception

[
  "include_once"
  "include"
  "require_once"
  "require"
  "use"
  "namespace"
] @keyword.import

[
  "declare"
  "echo"
  "enddeclare"
  "extends"
  "global"
  "goto"
  "implements"
  "insteadof"
  "print"
  "unset"
] @keyword

; Labels

(named_label_statement (name) @label)
(goto_statement (name) @label)

[
  (heredoc_start)
  (heredoc_end)
] @label
(heredoc "<<<" @label)
(nowdoc "<<<" @label)
(nowdoc "'" @label)

; Literals

(escape_sequence) @string.escape

[
  (string)
  (string_value)
  (nowdoc_body)
  (shell_command_expression)
] @string

(encapsed_string "\"" @string)

(boolean) @boolean
(null) @constant.builtin

((name) @constant.builtin
  (#match? @constant.builtin "^__[A-Z][A-Z\\d_]+__$"))

(integer) @number
(float) @number.float

; Builtins

(relative_scope) @variable.builtin

((variable_name) @variable.builtin
  (#match? @variable.builtin "^\\$(this|GLOBALS|_SERVER|_GET|_POST|_FILES|_REQUEST|_SESSION|_ENV|_COOKIE|argv|argc)$"))

[
  (primitive_type)
  (cast_type)
  (bottom_type)
] @type.builtin

((named_type (name) @type.builtin)
  (#match? @type.builtin "^(static|self|parent)$"))

(array_creation_expression "array" @function.builtin)
(list_literal "list" @function.builtin)

((function_call_expression
  function: (name) @function.builtin)
  (#match? @function.builtin "^(abs|array|array_[a-z_]+|arsort|asort|assert|boolval|call_user_func|call_user_func_array|ceil|chr|class_exists|compact|count|current|date|define|defined|die|dirname|echo|empty|end|error_log|exit|explode|extract|file|file_exists|file_get_contents|file_put_contents|filter_var|floatval|floor|fclose|fopen|fread|func_get_args|function_exists|fwrite|get_class|get_object_vars|gettype|header|htmlspecialchars|http_response_code|implode|in_array|intdiv|intval|is_[a-z_]+|isset|iterator_to_array|json_decode|json_encode|key|krsort|ksort|lcfirst|list|ltrim|max|mb_[a-z_]+|method_exists|microtime|min|mktime|next|nl2br|number_format|ob_get_clean|ob_start|ord|preg_[a-z_]+|print|print_r|printf|property_exists|range|reset|round|rsort|rtrim|serialize|settype|sleep|sort|spl_autoload_register|sprintf|str_[a-z_]+|strcmp|strlen|strpos|strrev|strrpos|strstr|strtolower|strtotime|strtoupper|strval|substr|time|trigger_error|trim|uasort|ucfirst|ucwords|uksort|unserialize|unset|urlencode|usleep|usort|var_dump|var_export|vsprintf)$"))

; `new static` / `new self` / `new parent`
((object_creation_expression (name) @variable.builtin)
  (#match? @variable.builtin "^(static|self|parent)$"))

; Constructors, functions, methods

(method_declaration
  name: (name) @constructor
  (#eq? @constructor "__construct"))

(object_creation_expression
  [
    (name) @constructor
    (qualified_name (name) @constructor)
  ])

(method_declaration
  name: (name) @function.method)

(use_instead_of_clause
  (class_constant_access_expression
    (_)
    (name) @function.method))

(use_as_clause
  (class_constant_access_expression
    (_)
    (name) @function.method)*
  (name) @function.method)

(function_definition
  name: (name) @function)

; `use function Foo\bar;`
(namespace_use_declaration
  "function"
  (namespace_use_clause
    [
      (name) @function
      (qualified_name (name) @function)
    ]))

(namespace_use_group_clause
  "function"
  (namespace_name (name) @function .))

(scoped_call_expression
  name: (name) @function.method.call)

(member_call_expression
  name: (name) @function.method.call)

(nullsafe_member_call_expression
  name: (name) @function.method.call)

(function_call_expression
  function: [
    (name) @function.call
    (qualified_name (name) @function.call)
  ])

; Parameters

(declare_directive
  [
    "strict_types"
    "ticks"
    "encoding"
  ] @variable.parameter)

(simple_parameter
  name: (variable_name) @variable.parameter)

(variadic_parameter
  name: (variable_name) @variable.parameter)

(property_promotion_parameter
  name: (variable_name) @variable.parameter)

(argument
  name: (name) @variable.parameter)

; Members

(property_element
  (variable_name) @variable.member)

(member_access_expression
  name: (variable_name (name)) @variable.member)
(member_access_expression
  name: (name) @variable.member)

(nullsafe_member_access_expression
  name: (variable_name (name)) @variable.member)
(nullsafe_member_access_expression
  name: (name) @variable.member)

(scoped_property_access_expression
  name: (variable_name) @variable.member)

; Constants

; `Foo::class` — the grammar hands `class` back as a plain name.
((class_constant_access_expression (name) @keyword.type .)
  (#eq? @keyword.type "class"))

(const_element (name) @constant)
(enum_case (name) @constant)

(class_constant_access_expression
  (_)
  (name) @constant .)

; `use const Foo\BAR;`
(namespace_use_declaration
  "const"
  (namespace_use_clause
    [
      (name) @constant
      (qualified_name (name) @constant)
    ]))

(namespace_use_group_clause
  "const"
  (namespace_name (name) @constant .))

; Types

(namespace_aliasing_clause (name) @type)

(named_type
  [
    (name) @type
    (qualified_name (name) @type)
  ])

(class_declaration name: (name) @type)
(interface_declaration name: (name) @type)
(trait_declaration name: (name) @type)
(enum_declaration name: (name) @type)

(base_clause
  [
    (name) @type
    (qualified_name (name) @type)
  ])

(class_interface_clause
  [
    (name) @type
    (qualified_name (name) @type)
  ])

(use_declaration (name) @type)

; `use A, B { A::x insteadof B; }` — the trait named after `insteadof`.
(use_instead_of_clause (name) @type .)

(binary_expression
  operator: "instanceof"
  right: [
    (name) @type
    (qualified_name (name) @type)
  ])

; `use Foo\Bar;` and `use Foo\{Bar, Baz}`
(namespace_use_clause
  [
    (name) @type
    (qualified_name (name) @type)
  ])

(namespace_use_group_clause
  (namespace_name (name) @type .))

(scoped_call_expression
  scope: [
    (name) @type
    (qualified_name (name) @type)
  ])

(class_constant_access_expression
  .
  [
    (name) @type
    (qualified_name (name) @type)
  ])

(scoped_property_access_expression
  scope: [
    (name) @type
    (qualified_name (name) @type)
  ])

; Namespaces: every segment of a namespace path (the prefix of a qualified
; name, a `namespace` declaration, a grouped import's prefix). Introduced
; after the specific @type patterns so a grouped import's single-segment
; clause stays a type, and before the bare-name fallbacks below.

(namespace_name (name) @module)

; Bare-name fallbacks. Dotted names the theme doesn't know fall back to
; their head, so these paint as constant / type while ranking below every
; specific pattern above.

((name) @constant.uppercase
  (#match? @constant.uppercase "^_?[A-Z][A-Z\\d_]*$"))

((name) @type.capitalized
  (#match? @type.capitalized "^[A-Z]"))

; Variables

(variable_name) @variable
(dynamic_variable_name) @variable

; Operators — before the delimiter list so the ternary's ":" reads as one.

(conditional_expression
  "?" @operator
  ":" @operator)

[
  "="
  "."
  "-"
  "*"
  "/"
  "+"
  "%"
  "**"
  "~"
  "|"
  "^"
  "&"
  "<<"
  ">>"
  "->"
  "?->"
  "=>"
  "<"
  "<="
  ">="
  ">"
  "<>"
  "<=>"
  "=="
  "!="
  "==="
  "!=="
  "!"
  "&&"
  "||"
  "??"
  ".="
  "-="
  "+="
  "*="
  "/="
  "%="
  "**="
  "&="
  "|="
  "^="
  "<<="
  ">>="
  "??="
  "--"
  "++"
  "@"
  "::"
  "..."
  "?"
] @operator

; Punctuation

[
  ","
  ";"
  ":"
  "\\"
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket
