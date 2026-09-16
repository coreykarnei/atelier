; Identifier naming conventions

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z_]*$"))

((identifier) @constructor
 (#match? @constructor "^[A-Z]"))

; Builtin functions

((call
  function: (identifier) @function.builtin)
 (#match?
   @function.builtin
   "^(abs|all|any|ascii|bin|bool|breakpoint|bytearray|bytes|callable|chr|classmethod|compile|complex|delattr|dict|dir|divmod|enumerate|eval|exec|filter|float|format|frozenset|getattr|globals|hasattr|hash|help|hex|id|input|int|isinstance|issubclass|iter|len|list|locals|map|max|memoryview|min|next|object|oct|open|ord|pow|print|property|range|repr|reversed|round|set|setattr|slice|sorted|staticmethod|str|sum|super|tuple|type|vars|zip|__import__)$"))

; Function calls

(decorator) @function

(call
  function: (attribute attribute: (identifier) @function.method))
(call
  function: (identifier) @function)

; Function definitions

(function_definition
  name: (identifier) @function)

(identifier) @variable
(attribute attribute: (identifier) @property)
(type (identifier) @type)

; Literals

[
  (none)
  (true)
  (false)
] @constant.builtin

[
  (integer)
  (float)
] @number

(comment) @comment
(string) @string
(escape_sequence) @escape

(interpolation
  "{" @punctuation.special
  "}" @punctuation.special) @embedded

[
  "-"
  "-="
  "!="
  "*"
  "**"
  "**="
  "*="
  "/"
  "//"
  "//="
  "/="
  "&"
  "&="
  "%"
  "%="
  "^"
  "^="
  "+"
  "->"
  "+="
  "<"
  "<<"
  "<<="
  "<="
  "<>"
  "="
  ":="
  "=="
  ">"
  ">="
  ">>"
  ">>="
  "|"
  "|="
  "~"
  "@="
  "and"
  "in"
  "is"
  "not"
  "or"
] @operator

; Atelier patch: keyword buckets split the way nvim-treesitter does, so a
; theme can tell a definition from control flow.
[
  "def"
  "class"
  "lambda"
] @keyword.function

[
  "return"
  "yield"
] @keyword.return

[
  "if"
  "elif"
  "else"
  "match"
  "case"
] @conditional

[
  "for"
  "while"
] @repeat

[
  "import"
  "from"
] @include

[
  "as"
  "assert"
  "async"
  "await"
  "break"
  "continue"
  "del"
  "except"
  "exec"
  "finally"
  "global"
  "nonlocal"
  "pass"
  "print"
  "raise"
  "try"
  "with"
] @keyword
