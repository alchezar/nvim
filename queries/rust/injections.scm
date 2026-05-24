; This file REPLACES (not extends) the upstream rust/injections.scm.
; Reason: upstream added a generic catch-all that re-injects every macro's
; token_tree as rust with `injection.include-children`, which re-applies
; @string.rust on top of our SQL captures inside `sqlx::query!()` and beats
; them on display. We keep upstream's other useful injections (comment, regex,
; slint/html/json/xml detected via macro name) but drop the catch-all.

; ------------------------------------------------------------------------------
; Comments
[(line_comment) (block_comment)] @injection.content
  (#set! injection.language "comment")

; ------------------------------------------------------------------------------
; Macros whose name == the language (slint!, html!, json!, xml!)
((macro_invocation
   macro: [
     (scoped_identifier name: (_) @injection.language)
     (identifier) @injection.language
   ]
   (token_tree) @injection.content)
 (#any-of? @injection.language "slint" "html" "json" "xml")
 (#offset! @injection.content 0 1 0 -1)
 (#set! injection.include-children))

; ------------------------------------------------------------------------------
; Regex::new / RegexBuilder::new / RegexSet::new / RegexSetBuilder::new
((call_expression
   function: (scoped_identifier
     path: (identifier) @_regex
     name: (identifier) @_new)
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_regex "Regex" "RegexBuilder")
 (#eq? @_new "new")
 (#set! injection.language "regex"))

((call_expression
   function: (scoped_identifier
     path: (identifier) @_regex
     name: (identifier) @_new)
   arguments: (arguments (array_expression (raw_string_literal (string_content) @injection.content))))
 (#any-of? @_regex "RegexSet" "RegexSetBuilder")
 (#eq? @_new "new")
 (#set! injection.language "regex"))

; ------------------------------------------------------------------------------
; sqlx::query!("SELECT ..."), sqlx::query_as!(), sqlx::query_scalar!() etc.
; Captures the inner `string_content` so multi-line plain strings work the same
; as raw strings. Capturing the outer `string_literal` with `(#offset! 0 1 0 -1)`
; to strip quotes silently failed for multi-line plain strings - the language
; tree never created an SQL region for them.

((macro_invocation
   macro: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_macro)
   (token_tree (string_literal (string_content) @injection.content)))
 (#eq? @_crate "sqlx")
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

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
   (token_tree (string_literal (string_content) @injection.content)))
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

((macro_invocation
   macro: (identifier) @_macro
   (token_tree (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_macro
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; ------------------------------------------------------------------------------
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
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; sqlx::query_scalar::<...>("...")  -- turbofish, plain string
((call_expression
   function: (generic_function
     function: (scoped_identifier
       path: (identifier) @_crate
       name: (identifier) @_func))
   arguments: (arguments (string_literal (string_content) @injection.content)))
 (#eq? @_crate "sqlx")
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; sqlx::query_scalar(r"...")  -- no turbofish, raw string
((call_expression
   function: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_func)
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#eq? @_crate "sqlx")
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; sqlx::query_scalar("...")  -- no turbofish, plain string
((call_expression
   function: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_func)
   arguments: (arguments (string_literal (string_content) @injection.content)))
 (#eq? @_crate "sqlx")
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; ------------------------------------------------------------------------------
; Bare imports: `use sqlx::query_scalar;`  ->  query_scalar(...)

; query_scalar::<...>(r"...")
((call_expression
   function: (generic_function
     function: (identifier) @_func)
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; query_scalar::<...>("...")
((call_expression
   function: (generic_function
     function: (identifier) @_func)
   arguments: (arguments (string_literal (string_content) @injection.content)))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; query_scalar(r"...")
((call_expression
   function: (identifier) @_func
   arguments: (arguments (raw_string_literal (string_content) @injection.content)))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; query_scalar("...")
((call_expression
   function: (identifier) @_func
   arguments: (arguments (string_literal (string_content) @injection.content)))
 (#any-of? @_func
   "query" "query_as" "query_scalar"
   "query_with" "query_as_with" "query_scalar_with"
   "raw_sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

