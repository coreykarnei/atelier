; Rust highlights — Atelier revision (see ATELIER.md, patch 3).
;
; How the editor resolves conflicts (TreeSitterClient+Highlight.swift): one
; capture per range, and the winner is the capture with the lowest *capture
; index* — i.e. the capture NAME that is mentioned first in this file. Pattern
; order is irrelevant; the first mention of each name sets its priority. This
; file is therefore laid out so names appear in priority order:
;
;   comment · literals · keyword.{function,import,conditional,repeat,return,
;   operator} · label · function.macro · attribute · punctuation.special ·
;   constant · type.builtin · type · constructor · function.builtin ·
;   function.method · function · namespace · variable.parameter · property ·
;   keyword · variable.builtin · punctuation.delimiter · punctuation.bracket ·
;   operator · variable
;
; Bucket names are nvim-treesitter's, restricted to what CaptureName.fromString
; places. Only #match? / #eq? / #not-match? / #not-eq? predicates resolve.
; Checked against the bundled grammar with Scripts/hlcheck (older
; tree-sitter-rust: no doc_comment markers, no type_parameter/never_type,
; no `raw`/`gen` tokens, field_initializer has no `field:` field).

; -------
; Comments (and the `_` placeholder, drawn as unused)
; -------

(shebang) @comment
(line_comment) @comment
(block_comment) @comment

; `let _ =`, `Hit(_)`, `|_|`, `Vec<_>`
"_" @comment
((type_arguments (type_identifier) @comment)
 (#eq? @comment "_"))

; -------
; Literals
; -------

(escape_sequence) @string.escape
[
  (string_literal)
  (raw_string_literal)
] @string
(char_literal) @character
(integer_literal) @number
(float_literal) @number.float
(boolean_literal) @boolean

; -------
; Keywords the theme draws apart from the plain keyword bucket
; -------

"fn" @keyword.function

"use" @keyword.import
(mod_item "mod" @keyword.import !body)
(use_as_clause "as" @keyword.import)
(extern_crate_declaration
  "extern" @keyword.import
  (crate) @keyword.import)

[
  "if"
  "else"
  "match"
  "try"
] @keyword.conditional

(for_expression "for" @keyword.repeat)
[
  "in"
  "while"
  "loop"
] @keyword.repeat

[
  "return"
  "break"
  "continue"
  "yield"
] @keyword.return

(type_cast_expression "as" @keyword.operator)

; -------
; Lifetimes and loop labels
; -------

(lifetime
  "'" @label
  (identifier) @label)
(label
  "'" @label
  (identifier) @label)

; -------
; Macros and attributes
; -------

(macro_invocation
  macro: (identifier) @function.macro
  "!" @function.macro)
(macro_invocation
  macro: (scoped_identifier
    name: (identifier) @function.macro)
  "!" @function.macro)
(macro_definition
  name: (identifier) @function.macro)
"macro_rules!" @function.macro

(attribute
  (identifier) @attribute)
(attribute
  (scoped_identifier
    name: (identifier) @attribute))
(attribute_item "#" @punctuation.special)
(inner_attribute_item
  "#" @punctuation.special
  "!" @punctuation.special)
(token_repetition_pattern
  ["$" "(" ")"] @punctuation.special)

; -------
; Identifier conventions: constants, types, constructors
; -------

; ALL_CAPS names are constants (two or more characters, so `T` stays a type).
((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]+$"))

(primitive_type) @type.builtin
((type_identifier) @type.builtin
 (#match? @type.builtin "^(Self|Box|String|Vec|Option|Result|HashMap|HashSet|BTreeMap|BTreeSet|Rc|Arc|Cell|RefCell|Mutex|RwLock|Send|Sized|Sync|Unpin|Drop|Fn|FnMut|FnOnce|AsMut|AsRef|From|Into|TryFrom|TryInto|Iterator|IntoIterator|DoubleEndedIterator|ExactSizeIterator|FromIterator|Extend|Clone|Copy|Debug|Default|Display|Eq|Hash|Ord|PartialEq|PartialOrd|ToOwned|ToString)$"))

(type_identifier) @type
(fragment_specifier) @type

; Uppercase names in paths are types (`Player::new`, `Outcome::Hit`).
((scoped_identifier
  path: (identifier) @type)
 (#match? @type "^[A-Z]"))
((scoped_identifier
  path: (scoped_identifier
    name: (identifier) @type))
 (#match? @type "^[A-Z]"))
((scoped_type_identifier
  path: (identifier) @type)
 (#match? @type "^[A-Z]"))
((scoped_type_identifier
  path: (scoped_identifier
    name: (identifier) @type))
 (#match? @type "^[A-Z]"))

; Uppercase names being imported are types (`use std::fmt::{self, Display}`).
((use_list (identifier) @type)
 (#match? @type "^[A-Z]"))
((use_declaration
  argument: (scoped_identifier name: (identifier) @type))
 (#match? @type "^[A-Z]"))
((use_as_clause
  path: (scoped_identifier name: (identifier) @type))
 (#match? @type "^[A-Z]"))

; `#[derive(Debug, Clone)]` names traits.
(attribute
  (identifier)
  arguments: (token_tree (identifier) @type))

; Remaining uppercase names are constructors / enum variants (`Ok(x)`,
; `None`, `Outcome::Miss`, the variants of an `enum`).
((identifier) @constructor
 (#match? @constructor "^[A-Z]"))
(struct_pattern
  type: (scoped_type_identifier
    name: (type_identifier) @constructor))
(tuple_struct_pattern
  type: (scoped_identifier
    name: (identifier) @constructor))
(enum_variant
  name: (identifier) @constructor)

; -------
; Functions
; -------

((call_expression
  function: (identifier) @function.builtin)
 (#match? @function.builtin "^(drop|size_of|size_of_val|align_of|align_of_val)$"))

(call_expression
  function: (field_expression
    field: (field_identifier) @function.method))
(generic_function
  function: (field_expression
    field: (field_identifier) @function.method))

(call_expression
  function: (identifier) @function)
(call_expression
  function: (scoped_identifier
    name: (identifier) @function))
(generic_function
  function: (identifier) @function)
(generic_function
  function: (scoped_identifier
    name: (identifier) @function))

; `f(foo::bar::baz)` — the last segment of a path passed as an argument can
; only be a function (modules aren't values).
(call_expression
  arguments: (arguments
    (scoped_identifier
      name: (identifier) @function)))

(function_item
  name: (identifier) @function)
(function_signature_item
  name: (identifier) @function)

; -------
; Paths, imports, modules — whatever is left in a path is a module
; -------

(use_declaration
  argument: (identifier) @namespace)
(use_declaration
  argument: (scoped_identifier name: (identifier) @namespace))
(use_wildcard
  (identifier) @namespace)
(extern_crate_declaration
  name: (identifier) @namespace
  alias: (identifier)? @namespace)
(mod_item
  name: (identifier) @namespace)
(scoped_use_list
  path: (identifier)? @namespace)
(scoped_use_list
  path: (scoped_identifier name: (identifier) @namespace))
(use_list
  (identifier) @namespace)
(use_as_clause
  path: (identifier)? @namespace
  alias: (identifier) @namespace)

(scoped_identifier
  path: (identifier) @namespace)
(scoped_identifier
  path: (scoped_identifier
    name: (identifier) @namespace))
(scoped_type_identifier
  path: (identifier) @namespace)
(scoped_type_identifier
  path: (scoped_identifier
    name: (identifier) @namespace))

; -------
; Parameters and fields
; -------

(metavariable) @variable.parameter
(parameter
  pattern: (identifier) @variable.parameter)
(parameter
  pattern: (mut_pattern (identifier) @variable.parameter))
(closure_parameters
  (identifier) @variable.parameter)
(closure_parameters
  (mut_pattern (identifier) @variable.parameter))

(field_initializer
  (field_identifier) @property)
(shorthand_field_initializer
  (identifier) @property)
(shorthand_field_identifier) @property
(field_expression
  field: (field_identifier) @property)
(field_identifier) @property

; -------
; Plain keywords
; -------

(use_list (self) @keyword)
(scoped_use_list (self) @keyword)
(scoped_identifier (self) @keyword)

[
  (crate)
  (super)
  (mutable_specifier)
  "as"
  "async"
  "await"
  "const"
  "default"
  "dyn"
  "enum"
  "extern"
  "for"
  "impl"
  "let"
  "mod"
  "move"
  "pub"
  "ref"
  "static"
  "struct"
  "trait"
  "type"
  "union"
  "unsafe"
  "where"
] @keyword

(self) @variable.builtin

; -------
; Punctuation and operators
; -------

[
  "::"
  "."
  ";"
  ","
  ":"
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket
(type_arguments ["<" ">"] @punctuation.bracket)
(type_parameters ["<" ">"] @punctuation.bracket)
(for_lifetimes ["<" ">"] @punctuation.bracket)
(bracketed_type ["<" ">"] @punctuation.bracket)
(closure_parameters "|" @punctuation.bracket)

[
  "?"
  "*"
  "'"
  "->"
  "=>"
  "<="
  "="
  "=="
  "!"
  "!="
  "%"
  "%="
  "&"
  "&="
  "&&"
  "|"
  "|="
  "||"
  "^"
  "^="
  "*="
  "-"
  "-="
  "+"
  "+="
  "/"
  "/="
  ">"
  "<"
  ">="
  ">>"
  "<<"
  ">>="
  "<<="
  "@"
  ".."
  "..="
  "..."
] @operator

; -------
; Everything else that is a name
; -------

(identifier) @variable
