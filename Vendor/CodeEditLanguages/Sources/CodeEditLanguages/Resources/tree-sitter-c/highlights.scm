; C highlights — ported from nvim-treesitter / Helix for the bundled grammar.
; The editor resolves one capture per range: the pattern that appears
; EARLIEST in this file wins, so specific patterns precede generic ones and
; the (identifier) @variable catch-all is last. cpp and objc inherit this
; file (their own queries are prepended), so only nodes shared by all three
; grammars belong here. Only #match? / #not-match? / #eq? / #not-eq? resolve.

; Comments

((comment) @comment.documentation
  (#match? @comment.documentation "^/\\*[\\*!][^\\*]"))

((comment) @comment.documentation
  (#match? @comment.documentation "^//[/!]"))

(comment) @comment

; Preprocessor

"#include" @keyword.import

(preproc_include
  path: (system_lib_string) @string.special)

[
  "#define"
  "#if"
  "#ifdef"
  "#ifndef"
  "#else"
  "#elif"
  "#endif"
  (preproc_directive)
] @keyword

(preproc_def
  name: (identifier) @constant.macro)

(preproc_function_def
  name: (identifier) @function.macro)

(preproc_params
  (identifier) @variable.parameter)

(preproc_ifdef
  name: (identifier) @constant.macro)

(preproc_defined
  "defined" @function.macro)

(preproc_defined
  (identifier) @constant.macro)

((preproc_call
  directive: (preproc_directive) @_u
  argument: (preproc_arg) @constant.macro)
  (#eq? @_u "#undef"))

; Attributes

(attribute
  name: (identifier) @attribute)

(attribute_specifier
  (argument_list
    (identifier) @attribute))

(attribute_specifier
  (argument_list
    (call_expression
      function: (identifier) @attribute)))

[
  "__attribute__"
  "__declspec"
  "__based"
  "__cdecl"
  "__clrcall"
  "__stdcall"
  "__fastcall"
  "__thiscall"
  "__vectorcall"
  (ms_pointer_modifier)
] @attribute

; Keywords

"return" @keyword.return

[
  "if"
  "else"
  "switch"
  "case"
  "default"
] @keyword.conditional

[
  "for"
  "while"
  "do"
  "break"
  "continue"
] @keyword.repeat

[
  "struct"
  "union"
  "enum"
  "typedef"
] @keyword.type

[
  "sizeof"
  "offsetof"
] @keyword.operator

[
  "goto"
] @keyword

(storage_class_specifier) @keyword.storage

(linkage_specification
  "extern" @keyword.storage)

(type_qualifier) @keyword.modifier

; Labels

(statement_identifier) @label

; Literals

(escape_sequence) @string.escape

(string_literal) @string

(system_lib_string) @string

(char_literal) @character

[
  (true)
  (false)
] @boolean

(null) @constant.builtin

((number_literal) @number.float
  (#match? @number.float "^([0-9]*\\.[0-9]*([eE][-+]?[0-9]+)?|[0-9]+[eE][-+]?[0-9]+|0[xX][0-9a-fA-F]*(\\.[0-9a-fA-F]*)?[pP][-+]?[0-9]+)[fFlL]*$"))

(number_literal) @number

; Functions

((call_expression
  function: (identifier) @function.builtin)
  (#match? @function.builtin "^__builtin_"))

((call_expression
  function: (identifier) @function.builtin)
  (#match? @function.builtin "^(printf|fprintf|sprintf|snprintf|vprintf|vfprintf|vsnprintf|puts|fputs|putchar|putc|fputc|getchar|getc|fgetc|fgets|gets|scanf|fscanf|sscanf|fopen|fclose|fread|fwrite|fflush|fseek|ftell|rewind|feof|ferror|perror|remove|rename|malloc|calloc|realloc|free|aligned_alloc|exit|abort|atexit|assert|abs|labs|llabs|atoi|atol|atoll|atof|strtol|strtoul|strtoll|strtoull|strtod|strtof|rand|srand|qsort|bsearch|getenv|system|memcpy|memmove|memset|memcmp|memchr|strlen|strnlen|strcpy|strncpy|strcat|strncat|strcmp|strncmp|strcoll|strchr|strrchr|strstr|strtok|strdup|strndup|strerror|isalpha|isdigit|isalnum|isspace|isupper|islower|toupper|tolower|va_start|va_end|va_arg|va_copy|setjmp|longjmp|signal|raise|time|clock|difftime|mktime|strftime|localtime|gmtime|sqrt|pow|exp|log|log10|sin|cos|tan|floor|ceil|round|fabs|fmod)$"))

((call_expression
  function: (identifier) @function.macro)
  (#match? @function.macro "^[A-Z][A-Z0-9_]+$"))

(call_expression
  function: (identifier) @function.call)

(call_expression
  function: (field_expression
    field: (field_identifier) @function.call))

(function_declarator
  declarator: (identifier) @function)

(function_declarator
  declarator: (parenthesized_declarator
    (pointer_declarator
      declarator: (identifier) @function)))

(function_declarator
  declarator: (parenthesized_declarator
    (pointer_declarator
      declarator: (field_identifier) @function)))

; Parameters (declarator nesting: pointers, arrays, function pointers)

(parameter_declaration
  declarator: (identifier) @variable.parameter)

(parameter_declaration
  declarator: (_
    (identifier) @variable.parameter))

(parameter_declaration
  declarator: (_
    (_
      (identifier) @variable.parameter)))

(parameter_declaration
  declarator: (_
    (_
      (_
        (identifier) @variable.parameter))))

"..." @punctuation.special

; Types

(type_definition
  declarator: (type_identifier) @type.definition)

(primitive_type) @type.builtin

(sized_type_specifier) @type.builtin

; Standard typedefs the grammar lexes as plain type_identifier.
((type_identifier) @type.builtin
  (#match? @type.builtin "^(_Bool|_Complex|_Imaginary|bool|wchar_t|char8_t|char16_t|char32_t|ptrdiff_t|intptr_t|uintptr_t|intmax_t|uintmax_t|u?int(8|16|32|64)_t|u?int_(least|fast)(8|16|32|64)_t|FILE|va_list|jmp_buf|time_t|clock_t|off_t|ssize_t|pid_t|uid_t|gid_t|mode_t)$"))

(type_identifier) @type

; Members

(field_identifier) @variable.member

; Constants

(enumerator
  name: (identifier) @constant)

(case_statement
  value: (identifier) @constant)

((identifier) @constant.builtin
  (#match? @constant.builtin "^(stderr|stdin|stdout|errno|__FILE__|__LINE__|__DATE__|__TIME__|__STDC__|__STDC_VERSION__|__STDC_HOSTED__|__cplusplus|__OBJC__|__ASSEMBLER__|__BASE_FILE__|__FILE_NAME__|__INCLUDE_LEVEL__|__TIMESTAMP__|__clang__|__clang_major__|__clang_minor__|__clang_patchlevel__|__clang_version__|__GNUC__|__GNUC_MINOR__|__FUNCTION__|__func__|__PRETTY_FUNCTION__|__VA_ARGS__|__VA_OPT__)$"))

((identifier) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]+$"))

; Operators

(conditional_expression
  [
    "?"
    ":"
  ] @operator)

(comma_expression
  "," @operator)

[
  "="
  "-"
  "*"
  "/"
  "+"
  "%"
  "~"
  "|"
  "&"
  "^"
  "<<"
  ">>"
  "->"
  "<"
  "<="
  ">="
  ">"
  "=="
  "!="
  "!"
  "&&"
  "||"
  "-="
  "+="
  "*="
  "/="
  "%="
  "|="
  "&="
  "^="
  ">>="
  "<<="
  "--"
  "++"
] @operator

; Punctuation

[
  ";"
  ":"
  ","
  "."
] @punctuation.delimiter

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

; Variables (catch-all — keep last)

(identifier) @variable
