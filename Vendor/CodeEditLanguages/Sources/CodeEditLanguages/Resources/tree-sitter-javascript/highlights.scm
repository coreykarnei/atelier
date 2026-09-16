; JavaScript (ECMAScript) highlights — Atelier.
;
; Ported from nvim-treesitter's ecma + javascript queries and Helix's ecma
; query, reduced to the predicates this editor resolves (#match? #not-match?
; #eq? #not-eq?) and to the capture names the editor can place.
;
; Precedence: when two captures cover the same range the editor keeps the one
; with the lowest capture index, and tree-sitter numbers capture NAMES by
; their first mention in the combined query text. So the order in which a
; @name first appears below is its priority, and `(identifier) @variable` is
; mentioned last. This file is also the parent of
; tree-sitter-typescript/highlights.scm, which is combined *before* it (that
; file re-mentions the names that must outrank @type there), so every node
; and field here must exist in both the javascript and typescript grammars.

; Comments
;---------

((comment) @comment.documentation
  (#match? @comment.documentation "^/\\*\\*[^*/]"))

(comment) @comment

(hash_bang_line) @comment

; Strings, regex, numbers
;------------------------

(escape_sequence) @string.escape

(template_substitution
  [
    "${"
    "}"
  ] @punctuation.special)

[
  (string)
  (template_string)
] @string

(regex) @string.regex

(regex
  "/" @string.regex)

((number) @number.float
  (#match? @number.float "^[0-9_]*\\.[0-9_]+([eE][+-]?[0-9_]+)?$|^[0-9_]+[eE][+-]?[0-9_]+$"))

(number) @number

; Literals
;---------

[
  (true)
  (false)
] @boolean

[
  (null)
  (undefined)
] @constant.builtin

((identifier) @constant.builtin
  (#match? @constant.builtin "^(NaN|Infinity)$"))

[
  (this)
  (super)
] @variable.builtin

; Labels
;-------

(statement_identifier) @label

; Decorators
;-----------

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

; Builtins
;---------

((identifier) @type.builtin
  (#match? @type.builtin "^(Object|Function|Boolean|Symbol|Number|BigInt|Math|Date|String|RegExp|Map|Set|WeakMap|WeakSet|WeakRef|Promise|Proxy|Reflect|JSON|Intl|Atomics|Array|ArrayBuffer|SharedArrayBuffer|DataView|Int8Array|Uint8Array|Uint8ClampedArray|Int16Array|Uint16Array|Int32Array|Uint32Array|Float32Array|Float64Array|BigInt64Array|BigUint64Array|Error|EvalError|RangeError|ReferenceError|SyntaxError|TypeError|URIError|AggregateError)$"))

((identifier) @variable.builtin
  (#match? @variable.builtin "^(arguments|module|exports|console|window|document|globalThis|process)$"))

(call_expression
  function: (identifier) @function.builtin
  (#match? @function.builtin "^(eval|fetch|isFinite|isNaN|parseFloat|parseInt|decodeURI|decodeURIComponent|encodeURI|encodeURIComponent|require|alert|prompt|confirm|btoa|atob|structuredClone|setTimeout|clearTimeout|setInterval|clearInterval|queueMicrotask)$"))

; Namespace imports / exports
;----------------------------

(namespace_import
  (identifier) @module)

(namespace_export
  (identifier) @module)

; Special identifiers
;--------------------

([
  (identifier)
  (shorthand_property_identifier)
  (shorthand_property_identifier_pattern)
  (property_identifier)
] @constant
  (#match? @constant "^_*[A-Z][A-Z0-9_]+$"))

(new_expression
  constructor: (identifier) @constructor)

(new_expression
  constructor: (member_expression
    property: (property_identifier) @constructor))

((identifier) @type
  (#match? @type "^[A-Z]"))

; Function and method definitions
;--------------------------------

(function
  name: (identifier) @function)

(function_declaration
  name: (identifier) @function)

(generator_function
  name: (identifier) @function)

(generator_function_declaration
  name: (identifier) @function)

(method_definition
  name: (property_identifier) @constructor
  (#eq? @constructor "constructor"))

(method_definition
  name: [
    (property_identifier)
    (private_property_identifier)
  ] @function.method)

(pair
  key: (property_identifier) @function.method
  value: [
    (function)
    (arrow_function)
  ])

(assignment_expression
  left: (member_expression
    property: (property_identifier) @function.method)
  right: [
    (function)
    (arrow_function)
  ])

(variable_declarator
  name: (identifier) @function
  value: [
    (function)
    (arrow_function)
  ])

(assignment_expression
  left: (identifier) @function
  right: [
    (function)
    (arrow_function)
  ])

; Function and method calls
;--------------------------

(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (member_expression
    property: [
      (property_identifier)
      (private_property_identifier)
    ] @function.method.call))

(call_expression
  function: (await_expression
    (identifier) @function.call))

(call_expression
  function: (await_expression
    (member_expression
      property: [
        (property_identifier)
        (private_property_identifier)
      ] @function.method.call)))

; Parameters
;-----------
; This file is compiled against the typescript grammar too, where a parameter
; is always wrapped in required_parameter / optional_parameter — so the plain
; `(formal_parameters (identifier))` shape is structurally impossible there
; and tree-sitter rejects the whole query. The wildcard shapes below are valid
; in both grammars: a direct child whose text is a bare identifier (`a`,
; `b`), and an identifier one level down (`...rest`, `a = 1`, `[a, b]`).
; Destructured-object parameters (`{ x, y: z }`) sit at a depth that differs
; between the grammars and fall through to @variable in plain JavaScript;
; tree-sitter-typescript/highlights.scm covers them for TypeScript.

((formal_parameters
  (_) @variable.parameter)
  (#match? @variable.parameter "^[A-Za-z_$][A-Za-z0-9_$]*$"))

(formal_parameters
  (_
    (identifier) @variable.parameter))

(arrow_function
  parameter: (identifier) @variable.parameter)

; Properties
;-----------

(property_identifier) @variable.member

(shorthand_property_identifier) @variable.member

(private_property_identifier) @variable.member

(object_pattern
  (shorthand_property_identifier_pattern) @variable)

(object_pattern
  (object_assignment_pattern
    (shorthand_property_identifier_pattern) @variable))

; Variables (catch-all — keep last among identifier rules)
;----------------------------------------------------------

(identifier) @variable

; Operators and punctuation
;--------------------------

(ternary_expression
  [
    "?"
    ":"
  ] @operator)

(binary_expression
  "/" @operator)

[
  "-"
  "--"
  "-="
  "+"
  "++"
  "+="
  "*"
  "*="
  "**"
  "**="
  "/="
  "%"
  "%="
  "<"
  "<="
  "<<"
  "<<="
  "="
  "=="
  "==="
  "!"
  "!="
  "!=="
  "=>"
  ">"
  ">="
  ">>"
  ">>="
  ">>>"
  ">>>="
  "~"
  "^"
  "&"
  "|"
  "^="
  "&="
  "|="
  "&&"
  "||"
  "??"
  "&&="
  "||="
  "??="
  "..."
] @operator

[
  ";"
  "."
  ","
  ":"
  (optional_chain)
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Keywords
;---------

[
  "if"
  "else"
  "switch"
  "case"
] @keyword.conditional

(switch_default
  "default" @keyword.conditional)

[
  "import"
  "from"
  "as"
  "export"
] @keyword.import

(export_statement
  "default" @keyword)

[
  "for"
  "of"
  "do"
  "while"
] @keyword.repeat

"function" @keyword.function

"class" @keyword.type

[
  "return"
  "yield"
] @keyword.return

[
  "async"
  "await"
] @keyword.coroutine

[
  "new"
  "delete"
  "in"
  "instanceof"
  "typeof"
  "void"
] @keyword.operator

[
  "throw"
  "try"
  "catch"
  "finally"
] @keyword.exception

[
  "break"
  "continue"
  "const"
  "debugger"
  "extends"
  "get"
  "let"
  "set"
  "static"
  "target"
  "var"
  "with"
] @keyword
