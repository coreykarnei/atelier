; Dockerfile highlights — Atelier revision.
;
; The editor keeps one capture per range: the capture NAME mentioned first in
; this file wins, pattern order is irrelevant (Scripts/hlcheck/README.md).
; Names therefore appear in priority order:
;
;   comment · string.escape · string.special · string · number ·
;   keyword.import · keyword.operator · constant.builtin · variable.parameter ·
;   property · type · punctuation.special · keyword · punctuation.delimiter ·
;   operator · variable
;
; Buckets are nvim-treesitter's (restricted to what CaptureName.fromString
; places); Helix's dockerfile query is the other reference. Checked against
; the bundled grammar with Scripts/hlcheck — an older tree-sitter-dockerfile:
; no heredocs (heredoc_marker/heredoc_line/heredoc_block), `param` and
; `mount_param` are leaf tokens (no name/value fields), image_spec has no
; name/tag/digest fields (child nodes only), the json_string_array brackets
; are not addressable, COPY/ADD take paths only (no JSON form), and
; `ENV KEY value` accepts a single-token value only. Shell bodies after RUN /
; CMD / ENTRYPOINT (shell_command, shell_fragment) are left plain on purpose —
; they inject nothing here and read as prose.

; -------
; Comments
; -------

(comment) @comment

; -------
; Literals
; -------

(escape_sequence) @string.escape

; `python:3.12` / `@sha256:…` — the pin on an image, drawn apart from the name
[
  (image_tag)
  (image_digest)
] @string.special

[
  (double_quoted_string)
  (single_quoted_string)
  (json_string)
] @string

(expose_port) @number

((arg_instruction default: (unquoted_string) @number)
 (#match? @number "^[0-9]+$"))
((env_pair value: (unquoted_string) @number)
 (#match? @number "^[0-9]+$"))

; -------
; Keywords the theme draws apart from the plain keyword bucket
; -------

; FROM pulls a base image in; `COPY --from=stage` pulls from another stage.
"FROM" @keyword.import
((param) @keyword.import
 (#match? @keyword.import "^--from="))

"AS" @keyword.operator

(healthcheck_instruction "NONE" @constant.builtin)

; -------
; Flags: --platform=…, --chown=…, --chmod=…, --mount=…, --interval=…
; (leaf tokens in this grammar; the whole flag is one range)
; -------

[
  (param)
  (mount_param)
] @variable.parameter

; -------
; Keys: ARG name, ENV name, LABEL key
; -------

(arg_instruction name: (unquoted_string) @property)
(env_pair name: (unquoted_string) @property)
(label_pair key: (unquoted_string) @property)

; -------
; Images: the name and the stage alias both name an image
; -------

(image_name) @type
(image_alias) @type

; -------
; Variable expansion sigils and line continuations
; -------

(expansion
  [
    "$"
    "{"
    "}"
  ] @punctuation.special)

(line_continuation) @punctuation.special

; -------
; Instructions
; -------

[
  "RUN"
  "CMD"
  "LABEL"
  "EXPOSE"
  "ENV"
  "ADD"
  "COPY"
  "ENTRYPOINT"
  "VOLUME"
  "USER"
  "WORKDIR"
  "ARG"
  "ONBUILD"
  "STOPSIGNAL"
  "HEALTHCHECK"
  "SHELL"
  "MAINTAINER"
  "CROSS_BUILD"
] @keyword

; -------
; Punctuation and operators
; -------

(image_tag ":" @punctuation.delimiter)
(image_digest "@" @punctuation.delimiter)
(user_instruction ":" @punctuation.delimiter)

; Only the assignment `=` — the `=` inside a flag stays part of the flag.
(arg_instruction "=" @operator)
(env_pair "=" @operator)
(label_pair "=" @operator)

; -------
; Variables — `${X}` / `$X`
; -------

(expansion (variable) @variable)
