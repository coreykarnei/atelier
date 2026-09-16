; C++ highlights — ported from nvim-treesitter / Helix for the bundled grammar.
; This file is prepended to tree-sitter-c/highlights.scm (parentQueryURL).
; The editor keeps one capture per range: the capture NAME whose first
; appearance in the combined query is earliest wins. So the order in which
; names are introduced below is the priority order — constructor before
; function, function.method.call before function.call, type before module —
; and everything here outranks the C rules that follow it.
; Only #match? / #not-match? / #eq? / #not-eq? resolve (no two-capture #eq?).

; Preprocessor names are introduced here so they outrank the SCREAMING_CASE
; @constant rule below (which the C file would otherwise introduce later).

(preproc_def
  name: (identifier) @constant.macro)

(preproc_function_def
  name: (identifier) @function.macro)

; Casts parse as calls to identifiers — keyword them before any call rule.

((identifier) @keyword.operator
  (#match? @keyword.operator "^(static_cast|dynamic_cast|reinterpret_cast|const_cast)$"))

"static_assert" @function.builtin

; Constructors & destructors
; Inside a class body only constructors/destructors lack a return type, and
; the grammar then hands function_declarator a bare identifier (methods get a
; field_identifier).

(class_specifier
  body: (field_declaration_list
    (function_definition
      declarator: (function_declarator
        declarator: (identifier) @constructor))))

(class_specifier
  body: (field_declaration_list
    (declaration
      declarator: (function_declarator
        declarator: (identifier) @constructor))))

(struct_specifier
  body: (field_declaration_list
    (function_definition
      declarator: (function_declarator
        declarator: (identifier) @constructor))))

(struct_specifier
  body: (field_declaration_list
    (declaration
      declarator: (function_declarator
        declarator: (identifier) @constructor))))

(destructor_name
  "~" @constructor
  (identifier) @constructor)

; Out-of-class `Foo::Foo(...)` and `Foo(...)` / `ns::Foo(...)` construction.

((function_declarator
  declarator: (qualified_identifier
    name: (identifier) @constructor))
  (#match? @constructor "^[A-Z][a-z]"))

((call_expression
  function: (identifier) @constructor)
  (#match? @constructor "^[A-Z][a-z]"))

((call_expression
  function: (qualified_identifier
    name: (identifier) @constructor))
  (#match? @constructor "^[A-Z][a-z]"))

; Initialiser list: `: Base(0)` is a constructor, `: m_field(x)` a member.

((field_initializer
  (field_identifier) @constructor
  (argument_list))
  (#match? @constructor "^[A-Z]"))

; Method calls — introduced before function.call so they win the range.

(call_expression
  function: (field_expression
    field: (field_identifier) @function.method.call))

(call_expression
  function: (field_expression
    field: (template_method
      name: (field_identifier) @function.method.call)))

; Method declarations

(function_declarator
  declarator: (field_identifier) @function.method)

(function_declarator
  declarator: (template_method
    name: (field_identifier) @function.method))

; Free / qualified functions

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (qualified_identifier
    name: (qualified_identifier
      name: (identifier) @function)))

(function_declarator
  declarator: (qualified_identifier
    name: (qualified_identifier
      name: (qualified_identifier
        name: (identifier) @function))))

(function_declarator
  declarator: (template_function
    name: (identifier) @function))

(function_declarator
  declarator: (qualified_identifier
    name: (template_function
      name: (identifier) @function)))

(operator_name) @function

(call_expression
  function: (qualified_identifier
    name: (identifier) @function.call))

(call_expression
  function: (qualified_identifier
    name: (qualified_identifier
      name: (identifier) @function.call)))

(call_expression
  function: (qualified_identifier
    name: (qualified_identifier
      name: (qualified_identifier
        name: (identifier) @function.call))))

(call_expression
  function: (template_function
    name: (identifier) @function.call))

(call_expression
  function: (qualified_identifier
    name: (template_function
      name: (identifier) @function.call)))

(call_expression
  function: (qualified_identifier
    name: (qualified_identifier
      name: (template_function
        name: (identifier) @function.call))))

; Members

(field_initializer
  (field_identifier) @variable.member)

((identifier) @variable.member
  (#match? @variable.member "^m_[A-Za-z0-9_]+$"))

; Parameters

(optional_parameter_declaration
  declarator: (identifier) @variable.parameter)

(optional_parameter_declaration
  declarator: (_
    (identifier) @variable.parameter))

(variadic_parameter_declaration
  declarator: (variadic_declarator
    (identifier) @variable.parameter))

(variadic_parameter_declaration
  declarator: (reference_declarator
    (variadic_declarator
      (identifier) @variable.parameter)))

; Types

(concept_definition
  name: (identifier) @type.definition)

(alias_declaration
  name: (type_identifier) @type.definition)

(auto) @type.builtin

; A capitalised scope (`Shape::area`) is a class, not a namespace.
((namespace_identifier) @type
  (#match? @type "^[A-Z]"))

(namespace_identifier) @module

(using_declaration
  "namespace"
  (identifier) @module)

(using_declaration
  "namespace"
  (qualified_identifier
    name: (identifier) @module))

; Scoped enumerators: `Color::Red`

((qualified_identifier
  name: (identifier) @constant)
  (#match? @constant "^[A-Z]"))

; Constants

(this) @variable.builtin

(null
  "nullptr" @constant.builtin)

; Literals

(raw_string_literal) @string

; Keywords

[
  "try"
  "catch"
  "throw"
  "noexcept"
] @keyword.exception

[
  "class"
  "namespace"
  "template"
  "typename"
  "concept"
] @keyword.type

(using_declaration
  "using" @keyword.import)

(alias_declaration
  "using" @keyword.type)

[
  "co_await"
  "co_yield"
  "co_return"
] @keyword.coroutine

[
  "public"
  "private"
  "protected"
  "final"
  "virtual"
  "explicit"
  "friend"
  "mutable"
  "constexpr"
  "constinit"
  "consteval"
  (virtual_specifier)
] @keyword.modifier

[
  "new"
  "delete"
  "and"
  "or"
  "not"
  "xor"
  "bitand"
  "bitor"
  "compl"
  "and_eq"
  "or_eq"
  "xor_eq"
  "not_eq"
] @keyword.operator

(default_method_clause
  "default" @keyword)

[
  "decltype"
  "override"
  "using"
  "requires"
] @keyword

; Operators & punctuation

(template_argument_list
  [
    "<"
    ">"
  ] @punctuation.bracket)

(template_parameter_list
  [
    "<"
    ">"
  ] @punctuation.bracket)

"<=>" @operator

"::" @punctuation.delimiter
