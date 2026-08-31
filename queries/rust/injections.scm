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

; ------------------------------------------------------------------------------
; QueryBuilder::new("SELECT ...") - the seed fragment is SQL too.

; QueryBuilder::new(...) after `use sqlx::QueryBuilder;`
((call_expression
   function: (scoped_identifier
     path: (identifier) @_type
     name: (identifier) @_new)
   arguments: (arguments
     [(string_literal (string_content) @injection.content)
      (raw_string_literal (string_content) @injection.content)]))
 (#eq? @_type "QueryBuilder")
 (#eq? @_new "new")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; sqlx::QueryBuilder::new(...) - fully qualified path
((call_expression
   function: (scoped_identifier
     path: (scoped_identifier name: (identifier) @_type)
     name: (identifier) @_new)
   arguments: (arguments
     [(string_literal (string_content) @injection.content)
      (raw_string_literal (string_content) @injection.content)]))
 (#eq? @_type "QueryBuilder")
 (#eq? @_new "new")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; Turbofish: QueryBuilder::<Postgres>::new(...) / sqlx::QueryBuilder::<Postgres>::new(...)
((call_expression
   function: (scoped_identifier
     path: (generic_type
       type: [(type_identifier) @_type
              (scoped_identifier name: (identifier) @_type)])
     name: (identifier) @_new)
   arguments: (arguments
     [(string_literal (string_content) @injection.content)
      (raw_string_literal (string_content) @injection.content)]))
 (#eq? @_type "QueryBuilder")
 (#eq? @_new "new")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; ------------------------------------------------------------------------------
; redis::Script::new(r"...") - the body is a Lua script (redis.call, KEYS, ARGV).

; Script::new(...) after `use redis::Script;`
((call_expression
   function: (scoped_identifier
     path: (identifier) @_type
     name: (identifier) @_new)
   arguments: (arguments
     [(string_literal (string_content) @injection.content)
      (raw_string_literal (string_content) @injection.content)]))
 (#eq? @_type "Script")
 (#eq? @_new "new")
 (#set! injection.language "lua")
 (#set! injection.priority 110))

; redis::Script::new(...) - fully qualified path
((call_expression
   function: (scoped_identifier
     path: (scoped_identifier name: (identifier) @_type)
     name: (identifier) @_new)
   arguments: (arguments
     [(string_literal (string_content) @injection.content)
      (raw_string_literal (string_content) @injection.content)]))
 (#eq? @_type "Script")
 (#eq? @_new "new")
 (#set! injection.language "lua")
 (#set! injection.priority 110))

; ------------------------------------------------------------------------------
; `language=sql` tag: SQL that is built rather than handed to a query macro.
; Same marker JetBrains IDEs read. Inside a macro call the tag must sit within
; the parentheses - that is what the rust catch-all below tests for to leave the
; string alone; on a binding it goes either on the line above or between the `=`
; and the string, where a wrapped signature puts it.
;
; A plain `"..."` is captured whole and trimmed by `#offset!` rather than through
; its (string_content): a `\` line continuation splits that content into one node
; per line, and one injection per fragment loses the leading keyword of each -
; tree-sitter drops the first token of a statement it cannot complete.

; format!(/* language=sql */ "...") or the tag on its own line inside the call
((macro_invocation
   (token_tree
     [(line_comment) (block_comment)] @_tag
     .
     (string_literal) @injection.content))
 (#lua-match? @_tag "language=sql")
 (#offset! @injection.content 0 1 0 -1)
 (#set! injection.include-children)
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; format!(/* language=sql */ r"...")
((macro_invocation
   (token_tree
     [(line_comment) (block_comment)] @_tag
     .
     (raw_string_literal (string_content) @injection.content)))
 (#lua-match? @_tag "language=sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; // language=sql  ->  let / const SQL: &str = "..."; / static SQL: &str = "...";
((_
   (line_comment) @_tag
   .
   [(let_declaration value: (string_literal) @injection.content)
    (const_item value: (string_literal) @injection.content)
    (static_item value: (string_literal) @injection.content)])
 (#lua-match? @_tag "^//%s*language=sql")
 (#offset! @injection.content 0 1 0 -1)
 (#set! injection.include-children)
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; // language=sql  ->  let / const / static SQL: &str = r"...";
((_
   (line_comment) @_tag
   .
   [(let_declaration value: (raw_string_literal (string_content) @injection.content))
    (const_item value: (raw_string_literal (string_content) @injection.content))
    (static_item value: (raw_string_literal (string_content) @injection.content))])
 (#lua-match? @_tag "^//%s*language=sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; The same tag sitting after the `=`, which is where a wrapped binding puts it.
; The tag is `(_)` and not `[(line_comment) (block_comment)]` because comments are
; grammar extras: they are absent from the node types of every parent that can hold
; one, and naming them there makes tree-sitter reject the pattern as impossible.
([(let_declaration (_) @_tag . value: (string_literal) @injection.content)
  (const_item (_) @_tag . value: (string_literal) @injection.content)
  (static_item (_) @_tag . value: (string_literal) @injection.content)]
 (#lua-match? @_tag "language=sql")
 (#offset! @injection.content 0 1 0 -1)
 (#set! injection.include-children)
 (#set! injection.language "sql")
 (#set! injection.priority 110))

([(let_declaration (_) @_tag . value: (raw_string_literal (string_content) @injection.content))
  (const_item (_) @_tag . value: (raw_string_literal (string_content) @injection.content))
  (static_item (_) @_tag . value: (raw_string_literal (string_content) @injection.content))]
 (#lua-match? @_tag "language=sql")
 (#set! injection.language "sql")
 (#set! injection.priority 110))

; ------------------------------------------------------------------------------
; Generic macro bodies as rust (the upstream catch-all we dropped above).
; Re-injecting the token_tree is what gives macro contents real highlighting
; (keywords, calls, types) instead of bare lexical tokens. We exclude the sqlx
; query family so it stays SQL, and slint/html/json/xml (handled by name above).
((macro_invocation
   macro: [
     (scoped_identifier name: (_) @_macro_name)
     (identifier) @_macro_name
   ]
   (token_tree) @injection.content)
 (#not-any-of? @_macro_name
   "slint" "html" "json" "xml"
   "query" "query_as" "query_scalar"
   "query_unchecked" "query_as_unchecked" "query_scalar_unchecked")
 (#not-lua-match? @injection.content "language=sql")
 (#set! injection.language "rust")
 (#set! injection.include-children))

; macro_rules! BODIES are intentionally not injected: `$meta`/`$(...)+` break rust
; parsing (ERROR -> all @variable). Main tree + overlay rules in highlights.scm color them.

