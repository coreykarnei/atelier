; TypeScript highlights — Atelier.
;
; This file is PREPENDED to tree-sitter-javascript/highlights.scm (the parent
; query) when the editor highlights TypeScript. The editor keeps the capture
; with the lowest index per range, and tree-sitter numbers capture NAMES by
; first mention in the combined text — so a name first mentioned here outranks
; every name first mentioned in the parent. That is why this file opens with a
; priority preamble: the parent's constant / constant.builtin / attribute /
; constructor / module rules are repeated here so they keep beating the
; `(type_identifier)` / capitalised-identifier @type rules, and brackets and
; operators are mentioned before delimiters so `<`/`>` in type arguments stay
; brackets and conditional-type `? :` stay operators. Ported from
; nvim-treesitter's typescript query and Helix's _typescript query, reduced to
; the predicates this editor resolves and the captures it can place.

; Priority preamble (see header) — names that must outrank @type
;----------------------------------------------------------------

((identifier) @constant.builtin
  (#match? @constant.builtin "^(NaN|Infinity)$"))

(decorator
  "@" @attribute)

(decorator
  (identifier) @attribute)

(decorator
  (call_expression
    function: (identifier) @attribute))

(decorator
  (member_expression
    property: (property_identifier) @attribute))

(decorator
  (call_expression
    function: (member_expression
      property: (property_identifier) @attribute)))

(predefined_type) @type.builtin

((type_identifier) @type.builtin
  (#match? @type.builtin "^(Array|ReadonlyArray|Promise|PromiseLike|Awaited|Record|Partial|Required|Readonly|Pick|Omit|Exclude|Extract|NonNullable|ReturnType|Parameters|ConstructorParameters|InstanceType|ThisType|Uppercase|Lowercase|Capitalize|Uncapitalize|Map|Set|WeakMap|WeakSet|WeakRef|Function|Object|Date|RegExp|Error|Symbol|BigInt|Iterable|Iterator|IterableIterator|AsyncIterable|AsyncIterator|Generator|AsyncGenerator|ArrayLike|ArrayBuffer|DataView|Int8Array|Uint8Array|Uint8ClampedArray|Int16Array|Uint16Array|Int32Array|Uint32Array|Float32Array|Float64Array|BigInt64Array|BigUint64Array)$"))

([
  (identifier)
  (shorthand_property_identifier)
  (shorthand_property_identifier_pattern)
  (property_identifier)
] @constant
  (#match? @constant "^_*[A-Z][A-Z0-9_]+$"))

(enum_assignment
  name: (property_identifier) @constant)

(enum_body
  (property_identifier) @constant)

(new_expression
  constructor: (identifier) @constructor)

(new_expression
  constructor: (member_expression
    property: (property_identifier) @constructor))

; Namespaces
;-----------

(internal_module
  (identifier) @module)

(internal_module
  (nested_identifier
    (identifier) @module))

(internal_module
  (nested_identifier
    (property_identifier) @module))

(nested_type_identifier
  (identifier) @module)

(ambient_declaration
  "global" @module)

; Types
;------

(type_identifier) @type

(import_statement
  "type"
  (import_clause
    (named_imports
      (import_specifier
        name: (identifier) @type))))

(enum_declaration
  name: (identifier) @type)

(extends_clause
  value: (member_expression
    property: (property_identifier) @type))

; Function and method signatures
;-------------------------------

(function_signature
  name: (identifier) @function)

(method_signature
  name: (property_identifier) @function.method)

(abstract_method_signature
  name: (property_identifier) @function.method)

(property_signature
  name: (property_identifier) @function.method
  type: (type_annotation
    [
      (function_type)
      (union_type
        (parenthesized_type
          (function_type)))
    ]))

; Parameters
;-----------
; The typescript grammar wraps each parameter in required_parameter /
; optional_parameter; the parent's wildcard rules only reach the simple cases.

(required_parameter
  pattern: (identifier) @variable.parameter)

(optional_parameter
  pattern: (identifier) @variable.parameter)

(required_parameter
  (rest_pattern
    (identifier) @variable.parameter))

(optional_parameter
  (rest_pattern
    (identifier) @variable.parameter))

(required_parameter
  (object_pattern
    (shorthand_property_identifier_pattern) @variable.parameter))

(optional_parameter
  (object_pattern
    (shorthand_property_identifier_pattern) @variable.parameter))

(required_parameter
  (object_pattern
    (object_assignment_pattern
      (shorthand_property_identifier_pattern) @variable.parameter)))

(required_parameter
  (object_pattern
    (pair_pattern
      value: (identifier) @variable.parameter)))

(required_parameter
  (object_pattern
    (pair_pattern
      value: (assignment_pattern
        left: (identifier) @variable.parameter))))

(required_parameter
  (array_pattern
    (identifier) @variable.parameter))

(optional_parameter
  (array_pattern
    (identifier) @variable.parameter))

(required_parameter
  (array_pattern
    (rest_pattern
      (identifier) @variable.parameter)))

; Literals
;---------

(this_type) @variable.builtin

(template_literal_type) @string

; Punctuation and operators (order: special < bracket < operator < delimiter)
;---------------------------------------------------------------------------

(template_type
  [
    "${"
    "}"
  ] @punctuation.special)

(optional_parameter
  "?" @punctuation.special)

(optional_type
  "?" @punctuation.special)

(property_signature
  "?" @punctuation.special)

(method_signature
  "?" @punctuation.special)

(abstract_method_signature
  "?" @punctuation.special)

(method_definition
  "?" @punctuation.special)

(public_field_definition
  [
    "?"
    "!"
  ] @punctuation.special)

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

(conditional_type
  [
    "?"
    ":"
  ] @operator)

(non_null_expression
  "!" @operator)

(omitting_type_annotation
  "-?:" @punctuation.delimiter)

(opting_type_annotation
  "?:" @punctuation.delimiter)

; Keywords
;---------

(as_expression
  "as" @keyword.operator)

(mapped_type_clause
  "as" @keyword.operator)

[
  "keyof"
  "satisfies"
  "is"
  "asserts"
  "infer"
] @keyword.operator

[
  "namespace"
  "interface"
  "enum"
  "type"
] @keyword.type

"require" @keyword.import

[
  "abstract"
  "private"
  "protected"
  "public"
  "readonly"
  "override"
  "declare"
] @keyword.modifier

[
  "implements"
  "module"
] @keyword
