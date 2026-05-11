; extends

; ---------------------------------------------------------------------------
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
 (#set! injection.priority 110)
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
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; Bare query!() / query_as!() when imported via `use sqlx::query;`
((macro_invocation
   macro: (identifier) @_macro
   (token_tree (string_literal) @injection.content))
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql")
 (#set! injection.priority 110)
 (#offset! @injection.content 0 1 0 -1))

((macro_invocation
   macro: (identifier) @_macro
   (token_tree (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; ---------------------------------------------------------------------------
; Function-call forms (no `!`): sqlx::query_scalar::<_, Uuid>(r"SELECT ...")
; The turbofish content is unconstrained - any type args match.

; sqlx::query_scalar::<...>(r"...")  -- turbofish, raw string
((call_expression
   function: (generic_function
     function: (scoped_identifier
       path: (identifier) @_crate
       name: (identifier) @_func))
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#eq? @_crate "sqlx")
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; sqlx::query_scalar::<...>("...")  -- turbofish, plain string
((call_expression
   function: (generic_function
     function: (scoped_identifier
       path: (identifier) @_crate
       name: (identifier) @_func))
   arguments: (arguments (string_literal) @injection.content))
 (#eq? @_crate "sqlx")
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110)
 (#offset! @injection.content 0 1 0 -1))

; sqlx::query_scalar(r"...")  -- no turbofish, raw string
((call_expression
   function: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_func)
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#eq? @_crate "sqlx")
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; sqlx::query_scalar("...")  -- no turbofish, plain string
((call_expression
   function: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_func)
   arguments: (arguments (string_literal) @injection.content))
 (#eq? @_crate "sqlx")
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110)
 (#offset! @injection.content 0 1 0 -1))

; ---------------------------------------------------------------------------
; Bare imports: `use sqlx::query_scalar;`  ->  query_scalar(...)

; query_scalar::<...>(r"...")
((call_expression
   function: (generic_function
     function: (identifier) @_func)
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; query_scalar::<...>("...")
((call_expression
   function: (generic_function
     function: (identifier) @_func)
   arguments: (arguments (string_literal) @injection.content))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110)
 (#offset! @injection.content 0 1 0 -1))

; query_scalar(r"...")
((call_expression
   function: (identifier) @_func
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; query_scalar("...")
((call_expression
   function: (identifier) @_func
   arguments: (arguments (string_literal) @injection.content))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with")
 (#set! injection.language "sql")
 (#set! injection.priority 110)
 (#offset! @injection.content 0 1 0 -1))

