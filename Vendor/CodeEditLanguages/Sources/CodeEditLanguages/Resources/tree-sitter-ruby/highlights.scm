; Ruby highlights — ported from nvim-treesitter for Atelier's editor.
;
; Resolution rule: when two captures cover the same range, the one whose
; *name first appears earliest in this file* wins (lowest capture index), so
; the order of first appearance below is the priority order:
;   comment.documentation → comment → keyword buckets → builtins →
;   constructor → function → module → constant → type → calls →
;   parameters → members → literals → punctuation → operator → variable.
; Only #match?/#not-match?/#eq?/#not-eq? predicates resolve here.

; Comments — a run of comments immediately before a definition documents it.
; Comments are grammar extras: one preceding the first member of a class or
; module attaches to the class itself, ahead of its body_statement.

((comment)+ @comment.documentation
  .
  [(class) (module) (method) (singleton_method)])

((comment)+ @comment.documentation
  .
  (body_statement
    .
    [(class) (module) (method) (singleton_method)]))

(comment) @comment

; Keywords — declaration / return / operator / conditional / repeat /
; exception / import / modifier buckets, then the rest.

[
  "def"
  "undef"
] @keyword.function

[
  "class"
  "module"
] @keyword.type

[
  "return"
  "yield"
] @keyword.return

[
  "and"
  "or"
  "in"
  "not"
  "defined?"
] @keyword.operator

[
  "case"
  "else"
  "elsif"
  "if"
  "unless"
  "when"
  "then"
] @keyword.conditional

[
  "for"
  "until"
  "while"
  "break"
  "redo"
  "retry"
  "next"
] @keyword.repeat

[
  "begin"
  "rescue"
  "ensure"
] @keyword.exception

((call
  !receiver
  method: (identifier) @keyword.exception)
  (#match? @keyword.exception "^(raise|fail|catch|throw)$"))

((identifier) @keyword.exception
  (#match? @keyword.exception "^(raise|fail)$"))

((call
  !receiver
  method: (identifier) @keyword.import)
  (#match? @keyword.import "^(require|require_relative|load|autoload|include|extend|prepend|refine|using)$"))

((identifier) @keyword.modifier
  (#match? @keyword.modifier "^(private|protected|public|module_function|private_constant|private_class_method|public_class_method)$"))

[
  "alias"
  "do"
  "end"
] @keyword

; Builtins

[
  (self)
  (super)
] @variable.builtin

((global_variable) @variable.builtin
  (#match? @variable.builtin "^\\$(stdout|stderr|stdin|PROGRAM_NAME|LOAD_PATH|LOADED_FEATURES|DEBUG|VERBOSE|FILENAME|0|[!@&`'+~=/\\\\,;.<>_*$?:\"1-9])$"))

(nil) @constant.builtin

((identifier) @constant.builtin
  (#match? @constant.builtin "^__(callee|dir|id|method|send|ENCODING|FILE|LINE)__$"))

(file) @constant.builtin
(line) @constant.builtin
(encoding) @constant.builtin
(hash_splat_nil) @constant.builtin

((constant) @constant.builtin
  (#match? @constant.builtin "^(ENV|ARGV|ARGF|DATA|STDIN|STDOUT|STDERR|RUBY_VERSION|RUBY_PLATFORM|RUBY_ENGINE|RUBY_RELEASE_DATE|RUBY_PATCHLEVEL|RUBY_COPYRIGHT|RUBY_DESCRIPTION|TOPLEVEL_BINDING)$"))

[
  (true)
  (false)
] @boolean

((call
  !receiver
  method: (identifier) @function.builtin)
  (#match? @function.builtin "^(attr|attr_reader|attr_writer|attr_accessor|alias_method|define_method|remove_method|undef_method|puts|print|p|pp|gets|format|sprintf|printf|loop|lambda|proc|block_given\\?|binding|exit|exit!|abort|sleep|rand|srand|at_exit|warn|freeze|instance_variable_get|instance_variable_set|send|public_send|respond_to\\?|method_missing|Integer|Float|String|Array|Hash|Rational|Complex)$"))

((identifier) @function.builtin
  (#match? @function.builtin "^(block_given\\?|binding|exit|abort|gets|loop)$"))

; Constructors

((call
  method: (identifier) @constructor)
  (#eq? @constructor "new"))

; Function definitions

(method
  name: (identifier) @function)

(method
  name: (setter (identifier) @function))

(method
  name: (operator) @function)

(singleton_method
  name: (identifier) @function)

(singleton_method
  name: (setter (identifier) @function))

(singleton_method
  name: (operator) @function)

(alias
  (identifier) @function)

(undef
  (identifier) @function)

; Namespaces, constants, types

(module
  name: (constant) @module)

(module
  name: (scope_resolution
    name: (constant) @module))

(scope_resolution
  scope: (constant) @module)

((constant) @constant
  (#match? @constant "^[A-Z\\d_]+$"))

(method
  name: (constant) @type)

(singleton_method
  name: (constant) @type)

(class
  name: (constant) @type)

(class
  name: (scope_resolution
    name: (constant) @type))

(superclass
  (constant) @type)

(constant) @type

; Method calls

(call
  receiver: (_)
  method: [
    (identifier)
    (constant)
  ] @function.method.call)

(call
  method: [
    (identifier)
    (constant)
  ] @function.call)

; Parameters

(method_parameters
  (identifier) @variable.parameter)

(lambda_parameters
  (identifier) @variable.parameter)

(block_parameters
  (identifier) @variable.parameter)

(splat_parameter
  name: (identifier) @variable.parameter)

(hash_splat_parameter
  name: (identifier) @variable.parameter)

(block_parameter
  name: (identifier) @variable.parameter)

(optional_parameter
  name: (identifier) @variable.parameter)

(keyword_parameter
  name: (identifier) @variable.parameter)

(destructured_parameter
  (identifier) @variable.parameter)

; Members

[
  (instance_variable)
  (class_variable)
] @variable.member

; Literals

[
  (bare_symbol)
  (simple_symbol)
  (delimited_symbol)
  (hash_key_symbol)
] @string.special.symbol

(regex
  (string_content) @string.regex)

(regex) @string.regex

(escape_sequence) @string.escape

(subshell) @string.special

[
  (heredoc_beginning)
  (heredoc_end)
] @label

[
  (string_content)
  (heredoc_content)
  (bare_string)
  "\""
  "`"
] @string

(string) @string

(character) @character

[
  (integer)
  (rational)
  (complex)
] @number

(float) @number.float

; Punctuation — before operators so the pair colon, block-parameter bars
; and regex slashes claim their tokens.

(interpolation
  "#{" @punctuation.special
  "}" @punctuation.special)

(pair
  ":" @punctuation.delimiter)

(keyword_parameter
  ":" @punctuation.delimiter)

[
  ","
  ";"
  "."
  "&."
  "::"
] @punctuation.delimiter

(block_parameters
  "|" @punctuation.bracket)

(regex
  "/" @punctuation.bracket)

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "%w("
  "%i("
] @punctuation.bracket

; Operators

[
  "!"
  "="
  "=="
  "==="
  "<=>"
  "=>"
  "->"
  ">>"
  "<<"
  ">"
  "<"
  ">="
  "<="
  "**"
  "*"
  "/"
  "%"
  "+"
  "-"
  "&"
  "|"
  "^"
  "~"
  "&&"
  "||"
  "||="
  "&&="
  "!="
  "%="
  "+="
  "-="
  "*="
  "/="
  "**="
  "<<="
  ">>="
  "&="
  "|="
  "^="
  "=~"
  "!~"
  "?"
  ":"
  ".."
  "..."
] @operator

; Variables — the catch-all, last.

[
  (identifier)
  (global_variable)
] @variable
