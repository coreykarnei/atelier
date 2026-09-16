; Atelier: injection names are `TreeSitterLanguage` raw values — Swift case
; names — so nvim's "markdown_inline" and "yml" resolved to nothing and no
; inline highlighting ever reached the editor. Heading and block-quote
; inlines deliberately stay in this layer: an injected range is removed from
; the block layer's query, and the inline grammar knows nothing about
; headings or quotes, so their text could never be styled otherwise.
(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)

((html_block) @injection.content (#set! injection.language "html"))

((minus_metadata) @injection.content (#set! injection.language "yaml"))
((plus_metadata) @injection.content (#set! injection.language "toml"))

((section (paragraph (inline) @injection.content)) (#set! injection.language "markdownInline"))
((list_item (paragraph (inline) @injection.content)) (#set! injection.language "markdownInline"))
