; extends

; sqlx::query!("SELECT ..."), sqlx::query_as!(), sqlx::query_scalar!() etc.
; Captures the string contents and parses them as SQL.
; offset(0, 1, 0, -1) strips the surrounding quotes from "...".

((macro_invocation
   macro: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_macro)
   (token_tree (string_literal) @injection.content))
 (#eq? @_crate "sqlx")
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql")
 (#offset! @injection.content 0 1 0 -1))

; Same but for raw strings: sqlx::query!(r#"SELECT ..."#)
((macro_invocation
   macro: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_macro)
   (token_tree (raw_string_literal (string_content) @injection.content)))
 (#eq? @_crate "sqlx")
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql"))

; Bare query!() / query_as!() when imported via `use sqlx::query;`
((macro_invocation
   macro: (identifier) @_macro
   (token_tree (string_literal) @injection.content))
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql")
 (#offset! @injection.content 0 1 0 -1))

((macro_invocation
   macro: (identifier) @_macro
   (token_tree (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql"))

