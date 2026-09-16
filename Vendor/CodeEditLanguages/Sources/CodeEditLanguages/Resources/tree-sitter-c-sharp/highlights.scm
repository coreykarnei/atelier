;; C# highlights — ported from nvim-treesitter (c_sharp) and Helix (c-sharp)
;; onto the grammar bundled in CodeLanguagesContainer (tree-sitter-c-sharp
;; 0.20-era: `(modifier)` node, `*_directive` preprocessor nodes,
;; `type_of_expression`, no `returns:` field).
;;
;; Resolution rule: when two captures cover the same range, the capture
;; NAME that first appears earliest in this file wins. So the sections
;; below are ordered by priority of the name they introduce — comments,
;; keyword buckets, builtins, literals, attributes, labels, constants,
;; declarations/calls, types, modules, parameters, members, punctuation,
;; and the (identifier) @variable catch-all last. Only #match?/#not-match?/
;; #eq?/#not-eq? predicates resolve.

;; ── Comments ────────────────────────────────────────────────────────────

((comment) @comment.documentation
  (#match? @comment.documentation "^///"))
((comment) @comment.documentation
  (#match? @comment.documentation "^/\\*\\*[^*]"))
(comment) @comment

;; ── Preprocessor ────────────────────────────────────────────────────────

[
  (nullable_directive)
  (region_directive)
  (endregion_directive)
  (define_directive)
  (undef_directive)
  (if_directive)
  (elif_directive)
  (else_directive)
  (endif_directive)
  (line_directive)
  (pragma_directive)
  (error_directive)
  (warning_directive)
] @keyword.import
(preproc_message) @string

;; ── Keywords: specific buckets before the generic ones ──────────────────

(modifier "async" @keyword.coroutine)
"await" @keyword.coroutine

[
  "return"
  "yield"
] @keyword.return

[
  "if"
  "else"
  "switch"
  "case"
  "when"
  "break"
] @keyword.conditional

[
  "while"
  "for"
  "do"
  "foreach"
  "continue"
  "goto"
] @keyword.repeat

[
  "try"
  "catch"
  "throw"
  "finally"
] @keyword.exception

"using" @keyword.import

;; `nameof(x)` parses as a plain call in this grammar.
((invocation_expression
  function: (identifier) @keyword.operator)
  (#eq? @keyword.operator "nameof"))

[
  "new"
  "typeof"
  "sizeof"
  "is"
  "as"
  "and"
  "or"
  "not"
  "with"
  "stackalloc"
  "in"
  "out"
  "ref"
  "checked"
  "unchecked"
] @keyword.operator
(parameter_modifier) @keyword.operator

[
  "class"
  "struct"
  "interface"
  "enum"
  "record"
  "namespace"
  "event"
  "delegate"
] @keyword.type

[
  "operator"
  "implicit"
  "explicit"
] @keyword.function

(modifier) @keyword.modifier
[
  "const"
  "static"
  "extern"
  "readonly"
  "volatile"
  "required"
  "abstract"
  "private"
  "protected"
  "internal"
  "public"
  "partial"
  "sealed"
  "virtual"
  "override"
  "unsafe"
  "fixed"
  "notnull"
  "unmanaged"
  "global"
] @keyword.modifier

[
  "lock"
  "params"
  "default"
  "get"
  "set"
  "init"
  "add"
  "remove"
  "where"
  "alias"
  "from"
  "select"
  "group"
  "by"
  "into"
  "join"
  "on"
  "equals"
  "orderby"
  "ascending"
  "descending"
  "let"
] @keyword

;; ── Builtin values ──────────────────────────────────────────────────────

(this_expression) @variable.builtin
(base_expression) @variable.builtin
[
  "this"
  "base"
] @variable.builtin
(discard) @variable.builtin

;; `value` inside a property/indexer/event accessor.
((identifier) @variable.builtin
  (#eq? @variable.builtin "value"))

;; ── Literals ────────────────────────────────────────────────────────────

(boolean_literal) @boolean
(null_literal) @constant.builtin

(integer_literal) @number
(real_literal) @number.float

(escape_sequence) @string.escape
(character_literal) @character

[
  (string_literal)
  (verbatim_string_literal)
  (raw_string_literal)
  (interpolated_string_text)
  (interpolated_verbatim_string_text)
  "\""
  "$\""
  "@$\""
  "$@\""
] @string

(interpolation
  [
    "{"
    "}"
  ] @punctuation.special)

;; ── Attributes ──────────────────────────────────────────────────────────

(attribute
  name: (identifier) @attribute)
(attribute
  name: (qualified_name
    (identifier) @attribute))
(attribute
  name: (generic_name
    (identifier) @attribute))

;; ── Labels ──────────────────────────────────────────────────────────────

(labeled_statement
  (identifier) @label)
(goto_statement
  (identifier) @label)

;; ── Constants ───────────────────────────────────────────────────────────

(enum_member_declaration
  name: (identifier) @constant)

;; `const int MaxItems = …` (field or local)
(field_declaration
  (modifier) @_mod
  (variable_declaration
    (variable_declarator
      (identifier) @constant))
  (#eq? @_mod "const"))
(local_declaration_statement
  (modifier) @_mod
  (variable_declaration
    (variable_declarator
      (identifier) @constant))
  (#eq? @_mod "const"))

;; Preprocessor symbols: `#if DEBUG`, `#define TRACE`, `#pragma warning disable CS1591`
(if_directive (identifier) @constant)
(elif_directive (identifier) @constant)
(define_directive (identifier) @constant)
(undef_directive (identifier) @constant)
(pragma_directive (identifier) @constant)

;; ── Declarations ────────────────────────────────────────────────────────

(constructor_declaration
  name: (identifier) @constructor)
(destructor_declaration
  name: (identifier) @constructor)

(method_declaration
  name: (identifier) @function.method)
(local_function_statement
  name: (identifier) @function.method)
(delegate_declaration
  name: (identifier) @function)

;; ── Calls ───────────────────────────────────────────────────────────────

(invocation_expression
  function: (identifier) @function.call)
(invocation_expression
  function: (generic_name
    .
    (identifier) @function.call))
(invocation_expression
  (member_access_expression
    name: (identifier) @function.method))
(invocation_expression
  (member_access_expression
    name: (generic_name
      .
      (identifier) @function.method)))
(invocation_expression
  (conditional_access_expression
    (member_binding_expression
      name: (identifier) @function.method)))
(invocation_expression
  (conditional_access_expression
    (member_binding_expression
      name: (generic_name
        .
        (identifier) @function.method))))

;; ── Types ───────────────────────────────────────────────────────────────

(predefined_type) @type.builtin
(implicit_type) @type.builtin

;; `using Alias = A.B.C;` — the alias is a type name, the target a type.
(using_directive
  (name_equals
    (identifier) @type))
(using_directive
  (name_equals)
  (identifier) @type)
(using_directive
  (name_equals)
  (qualified_name
    (identifier) @type))
(using_directive
  (name_equals)
  (qualified_name
    (qualified_name
      (identifier) @type)))
(using_directive
  (name_equals)
  (qualified_name
    (qualified_name
      (qualified_name
        (identifier) @type))))

(interface_declaration
  name: (identifier) @type)
(class_declaration
  name: (identifier) @type)
(struct_declaration
  name: (identifier) @type)
(record_declaration
  name: (identifier) @type)
(record_struct_declaration
  name: (identifier) @type)
(enum_declaration
  name: (identifier) @type)

(object_creation_expression
  type: (identifier) @type)
(object_creation_expression
  type: (generic_name
    (identifier) @type))
(object_creation_expression
  type: (qualified_name
    (identifier) @type))

(generic_name
  (identifier) @type)
(base_list
  (identifier) @type)
(base_list
  (qualified_name
    (identifier) @type))
(base_list
  (primary_constructor_base_type
    type: (identifier) @type))
(type_argument_list
  (identifier) @type)
(type_argument_list
  (qualified_name
    (identifier) @type))

;; Any `type:` field — declarations, parameters, casts, patterns, foreach…
(_ type: (identifier) @type)
(_ type: (qualified_name
  (identifier) @type))
(_ type: (qualified_name
  (qualified_name
    (identifier) @type)))
(_ type: (qualified_name
  (qualified_name
    (qualified_name
      (identifier) @type))))

(type_parameter
  (identifier) @type)
(type_parameter_constraints_clause
  target: (identifier) @type)
(type_parameter_constraint
  (type_constraint
    type: (identifier) @type))

(catch_declaration
  type: (identifier) @type)
(declaration_pattern
  type: (identifier) @type)
(as_expression
  right: (identifier) @type)
(is_expression
  right: (identifier) @type)
(type_of_expression
  (identifier) @type)
(cast_expression
  type: (identifier) @type)
(explicit_interface_specifier
  (identifier) @type)
(tuple_element
  type: (identifier) @type)
(nullable_type
  (identifier) @type)
(array_type
  (identifier) @type)
(pointer_type
  (identifier) @type)
(ref_type
  (identifier) @type)
(scoped_type
  (identifier) @type)

;; ── Namespaces ──────────────────────────────────────────────────────────
;; Dotted names nest as qualified_name chains (qualifier-first), so each
;; depth needs its own pattern to reach every segment.

(namespace_declaration
  name: (identifier) @module)
(namespace_declaration
  name: (qualified_name
    (identifier) @module))
(namespace_declaration
  name: (qualified_name
    (qualified_name
      (identifier) @module)))
(namespace_declaration
  name: (qualified_name
    (qualified_name
      (qualified_name
        (identifier) @module))))
(namespace_declaration
  name: (qualified_name
    (qualified_name
      (qualified_name
        (qualified_name
          (identifier) @module)))))

(file_scoped_namespace_declaration
  name: (identifier) @module)
(file_scoped_namespace_declaration
  name: (qualified_name
    (identifier) @module))
(file_scoped_namespace_declaration
  name: (qualified_name
    (qualified_name
      (identifier) @module)))
(file_scoped_namespace_declaration
  name: (qualified_name
    (qualified_name
      (qualified_name
        (identifier) @module))))
(file_scoped_namespace_declaration
  name: (qualified_name
    (qualified_name
      (qualified_name
        (qualified_name
          (identifier) @module)))))

(using_directive
  (identifier) @module)
(using_directive
  (qualified_name
    (identifier) @module))
(using_directive
  (qualified_name
    (qualified_name
      (identifier) @module)))
(using_directive
  (qualified_name
    (qualified_name
      (qualified_name
        (identifier) @module))))
(using_directive
  (qualified_name
    (qualified_name
      (qualified_name
        (qualified_name
          (identifier) @module)))))

;; ── Parameters ──────────────────────────────────────────────────────────

(parameter
  name: (identifier) @variable.parameter)
(parameter_list
  name: (identifier) @variable.parameter)
(bracketed_parameter_list
  name: (identifier) @variable.parameter)
(lambda_expression
  parameters: (identifier) @variable.parameter)
;; Named arguments: `Foo(count: 1)`, `[Obsolete("x", error: false)]`, tuple `(Left: 1)`
(argument
  (name_colon
    (identifier) @variable.parameter))
(attribute_argument
  (name_colon
    (identifier) @variable.parameter))

;; ── Members ─────────────────────────────────────────────────────────────

(property_declaration
  name: (identifier) @variable.member)
(event_declaration
  name: (identifier) @variable.member)
(event_field_declaration
  (variable_declaration
    (variable_declarator
      (identifier) @variable.member)))
(field_declaration
  (variable_declaration
    (variable_declarator
      (identifier) @variable.member)))
(initializer_expression
  (assignment_expression
    left: (identifier) @variable.member))
(with_initializer_expression
  (simple_assignment_expression
    (identifier) @variable.member))
(anonymous_object_creation_expression
  (identifier) @variable.member)
(attribute_argument
  (name_equals
    (identifier) @variable.member))
(member_access_expression
  name: (identifier) @variable.member)
(member_binding_expression
  name: (identifier) @variable.member)
(subpattern
  (expression_colon
    (identifier) @variable.member))

;; ── Punctuation & operators ─────────────────────────────────────────────

;; Generic angle brackets are brackets, not comparison operators — the
;; bracket name is introduced here so it outranks `operator` on `<`/`>`.
(type_argument_list
  [
    "<"
    ">"
  ] @punctuation.bracket)
(type_parameter_list
  [
    "<"
    ">"
  ] @punctuation.bracket)

[
  "+"
  "-"
  "*"
  "/"
  "%"
  "++"
  "--"
  "="
  "+="
  "-="
  "*="
  "/="
  "%="
  "&"
  "|"
  "^"
  "~"
  "&="
  "|="
  "^="
  "&&"
  "||"
  "!"
  "!="
  "=="
  "<"
  "<="
  ">"
  ">="
  "<<"
  ">>"
  ">>>"
  "<<="
  ">>="
  ">>>="
  "=>"
  "?"
  "??"
  "??="
  ".."
  "->"
] @operator

[
  ";"
  "."
  ","
  ":"
  "::"
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

;; ── Catch-all ───────────────────────────────────────────────────────────

(identifier) @variable
