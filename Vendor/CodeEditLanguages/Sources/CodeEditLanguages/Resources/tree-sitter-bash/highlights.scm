; Bash highlights — Atelier revision.
;
; The editor keeps one capture per range: the capture whose NAME is mentioned
; first in this file (see Scripts/hlcheck/README.md, "Precedence is by
; capture name"). Pattern order is irrelevant; the first mention of each name
; sets its priority, so the file is laid out in priority order:
;
;   comment · variable.parameter · boolean · number · string.regex · string ·
;   label · keyword.function · keyword.return · keyword.import ·
;   keyword.conditional · keyword.repeat · variable.builtin · function.builtin ·
;   function · function.call · string.special · punctuation.special · keyword ·
;   operator · punctuation.delimiter · punctuation.bracket · variable
;
; Bucket names are nvim-treesitter's, restricted to what CaptureName.fromString
; places. Only #match? / #eq? / #not-match? / #not-eq? predicates resolve
; (#any-of? lists are rewritten as #match? alternations). Checked against the
; bundled grammar with Scripts/hlcheck.

; -------
; Comments
; -------

(comment) @comment

; -------
; Options and flags: -x, --long, --key=value
; -------

((command
  argument: [
    (word) @variable.parameter
    (concatenation (word) @variable.parameter)
  ])
  (#match? @variable.parameter "^-"))
((declaration_command
  (word) @variable.parameter)
  (#match? @variable.parameter "^-"))
((unset_command
  (word) @variable.parameter)
  (#match? @variable.parameter "^-"))
((case_item
  value: [
    (word) @variable.parameter
    (extglob_pattern) @variable.parameter
  ])
  (#match? @variable.parameter "^-[-A-Za-z0-9_]*$"))

; -------
; Literals
; -------

((word) @boolean
  (#match? @boolean "^(true|false)$"))

(number) @number
(file_descriptor) @number
((word) @number
  (#match? @number "^[0-9]+$"))

[
  (regex)
  (extglob_pattern)
] @string.regex

[
  (string)
  (raw_string)
  (ansi_c_string)
  (heredoc_body)
] @string

; unquoted right-hand sides: `name=value`, `--exclude=.git`
(variable_assignment
  (word) @string)
(concatenation
  (word) @string)
(herestring_redirect
  (word) @string)
; single-word expansion defaults and array elements: `${X:-qa}`, `(pi.local "…")`
(expansion
  (word) @string)
(array
  (word) @string)
; unquoted literals in tests: `[[ $host == pi.local ]]`, `[ "$a" = b ]`
(test_command
  (binary_expression
    (word) @string))
(test_command
  (binary_expression
    (binary_expression
      (word) @string)))
(test_command
  (unary_expression
    (word) @string))

[
  (heredoc_start)
  (heredoc_end)
] @label

; -------
; Keywords the theme draws apart from the plain keyword bucket
; -------

"function" @keyword.function

((command_name
  (word) @keyword.return)
  (#match? @keyword.return "^(return|exit|break|continue)$"))

"export" @keyword.import

[
  "if"
  "then"
  "else"
  "elif"
  "fi"
  "case"
  "esac"
] @keyword.conditional
(case_statement "in" @keyword.conditional)
(ternary_expression
  [
    "?"
    ":"
  ] @keyword.conditional)

[
  "for"
  "do"
  "done"
  "select"
  "until"
  "while"
] @keyword.repeat
(for_statement "in" @keyword.repeat)

; -------
; Special and builtin variables: $?, $@, $#, $1, $HOME, $PATH …
; -------

(simple_expansion
  "$" @variable.builtin
  .
  (special_variable_name) @variable.builtin)
(expansion
  (special_variable_name) @variable.builtin)
((simple_expansion
  (variable_name) @variable.builtin)
  (#match? @variable.builtin "^[0-9]+$"))
((expansion
  (variable_name) @variable.builtin)
  (#match? @variable.builtin "^[0-9]+$"))
((subscript
  index: (word) @variable.builtin)
  (#match? @variable.builtin "^[@*]$"))

((variable_name) @variable.builtin
  (#match? @variable.builtin "^(CDPATH|HOME|IFS|MAIL|MAILPATH|OPTARG|OPTIND|PATH|PS1|PS2|_|BASH|BASHOPTS|BASHPID|BASH_ALIASES|BASH_ARGC|BASH_ARGV|BASH_ARGV0|BASH_CMDS|BASH_COMMAND|BASH_COMPAT|BASH_ENV|BASH_EXECUTION_STRING|BASH_LINENO|BASH_LOADABLES_PATH|BASH_REMATCH|BASH_SOURCE|BASH_SUBSHELL|BASH_VERSINFO|BASH_VERSION|BASH_XTRACEFD|CHILD_MAX|COLUMNS|COMP_CWORD|COMP_LINE|COMP_POINT|COMP_TYPE|COMP_KEY|COMP_WORDBREAKS|COMP_WORDS|COMPREPLY|COPROC|DIRSTACK|EMACS|ENV|EPOCHREALTIME|EPOCHSECONDS|EUID|EXECIGNORE|FCEDIT|FIGNORE|FUNCNAME|FUNCNEST|GLOBIGNORE|GROUPS|histchars|HISTCMD|HISTCONTROL|HISTFILE|HISTFILESIZE|HISTIGNORE|HISTSIZE|HISTTIMEFORMAT|HOSTFILE|HOSTNAME|HOSTTYPE|IGNOREEOF|INPUTRC|INSIDE_EMACS|LANG|LC_ALL|LC_COLLATE|LC_CTYPE|LC_MESSAGES|LC_NUMERIC|LC_TIME|LINENO|LINES|MACHTYPE|MAILCHECK|MAPFILE|OLDPWD|OPTERR|OSTYPE|PIPESTATUS|POSIXLY_CORRECT|PPID|PROMPT_COMMAND|PROMPT_DIRTRIM|PS0|PS3|PS4|PWD|RANDOM|READLINE_ARGUMENT|READLINE_LINE|READLINE_MARK|READLINE_POINT|REPLY|SECONDS|SHELL|SHELLOPTS|SHLVL|SRANDOM|TIMEFORMAT|TMOUT|TMPDIR|UID|USER|SHELL|TERM|EDITOR|PAGER|LOGNAME)$"))

; -------
; Functions and commands
; -------

((command_name
  (word) @function.builtin)
  (#match? @function.builtin "^(\\.|:|alias|bg|bind|builtin|caller|cd|command|compgen|complete|compopt|coproc|dirs|disown|echo|enable|eval|exec|false|fc|fg|getopts|hash|help|history|jobs|kill|let|logout|mapfile|popd|printf|pushd|pwd|read|readarray|set|shift|shopt|source|suspend|test|time|times|trap|true|type|typeset|ulimit|umask|unalias|wait)$"))

(function_definition
  name: (word) @function)

(command_name
  (word) @function.call)

; -------
; Redirect targets: `> /dev/null`, `>> "$log"`
; -------

(file_redirect
  (word) @string.special)

; -------
; Expansion and substitution punctuation
; -------

(simple_expansion
  "$" @punctuation.special)
(expansion
  "${" @punctuation.special
  "}" @punctuation.special)
(expansion
  operator: _ @punctuation.special)
(command_substitution
  "$(" @punctuation.special
  ")" @punctuation.special)
(process_substitution
  [
    "<("
    ">("
  ] @punctuation.special
  ")" @punctuation.special)
(arithmetic_expansion
  [
    "$(("
    "(("
  ] @punctuation.special
  "))" @punctuation.special)
"`" @punctuation.special

; -------
; Plain keywords
; -------

[
  "declare"
  "typeset"
  "readonly"
  "local"
  "unset"
  "unsetenv"
] @keyword

; -------
; Operators: redirections, pipes, tests, arithmetic
; -------

[
  ">"
  ">>"
  "<"
  "<<"
  "&&"
  "|"
  "|&"
  "||"
  "="
  "+="
  "=~"
  "=="
  "!="
  "&>"
  "&>>"
  "<&"
  ">&"
  ">|"
  "<&-"
  ">&-"
  "<<-"
  "<<<"
  ".."
  "!"
  "[["
  "]]"
] @operator

(test_operator) @operator
(binary_expression
  operator: _ @operator)
(unary_expression
  operator: _ @operator)
(postfix_expression
  operator: _ @operator)

; -------
; Punctuation
; -------

[
  ";"
  ";;"
  ";&"
  ";;&"
  "&"
] @punctuation.delimiter
(arithmetic_expansion
  "," @punctuation.delimiter)

[
  "("
  ")"
  "{"
  "}"
  "["
  "]"
  "(("
  "))"
] @punctuation.bracket

; -------
; Variables (catch-all, last)
; -------

(variable_name) @variable
; bare names in a C-style for header are (word), not (variable_name):
; `for ((i = 1; i <= RETRIES; i++))`. Inside `$(( ))` they are (variable_name)
; already; inside `[[ ]]` they are literals and take @string above.
(c_style_for_statement
  (binary_expression
    (word) @variable))
(c_style_for_statement
  (binary_expression
    (binary_expression
      (word) @variable)))
(c_style_for_statement
  (unary_expression
    (word) @variable))
(c_style_for_statement
  (postfix_expression
    (word) @variable))
