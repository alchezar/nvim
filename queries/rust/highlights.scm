; extends

; Force comment color to win over markdown/rustdoc injection
; (priority > default 100 makes @comment.rust override injected captures)
((line_comment) @comment.rust (#set! priority 110))
((block_comment) @comment.rust (#set! priority 110))

; redis::cmd("GETDEL") - color the command name like a keyword, not a string
((call_expression
   function: (scoped_identifier
     path: (identifier) @_crate
     name: (identifier) @_cmd)
   arguments: (arguments (string_literal (string_content) @keyword)))
 (#eq? @_crate "redis")
 (#eq? @_cmd "cmd")
 (#set! priority 110))

; Overlay highlights for macro_rules! bodies, which carry no rust injection (see
; injections.scm). The main tree parses these as a flat token_tree, so we infer
; roles positionally. High priority so they win inside the macro body.
;
; `token_tree`/`token_repetition` also wrap attribute args (`#[utoipa::path(...)]`)
; and macro-call args, so every positional rule below is gated with
; `(#has-ancestor? @cap macro_definition)` - else `params(...)`/`responses(...)`
; inside an attribute would get @function.call (green) over their LSP token.

; Metavariables ($event_type, $ctx, $pat ...) as parameters (orange), like
; RustRover. Default capture is @function.macro (teal) shared with macro calls;
; this re-targets only the metavariable node, leaving `warn!` etc untouched.
; (metavariable/fragment_specifier nodes only exist in macro_rules - no gate.)
((metavariable) @variable.parameter
 (#set! priority 200))

; Fragment specifiers (`expr`, `pat`, `ty`, `ident` ...) - the type after `:` in
; `$name:expr`. They get no capture by default (rendered white). Own group so the
; color is independent of @type.builtin (defined as teal in the theme).
((fragment_specifier) @type.fragment
 (#set! priority 200))

; (Both `token_tree` and `token_repetition` containers - `$(...)+` arms put their
; tokens under token_repetition, plain bodies under token_tree.)

; Each rule is written twice - once for token_tree (plain bodies) and once for
; token_repetition (`$(...)+` arms put their tokens under that node instead).

; Calls: `name(` / `.name(` (identifier immediately before a `(`-token_tree).
((token_tree (identifier) @function.call . (token_tree . "("))
 (#has-ancestor? @function.call macro_definition) (#set! priority 200))
((token_repetition (identifier) @function.call . (token_tree . "("))
 (#has-ancestor? @function.call macro_definition) (#set! priority 200))

; Turbofish calls: `name::<...>(` - identifier before `::<`. Lowercase-only so
; type paths like `Foo::<T>` stay a type, not a function.
((token_tree (identifier) @function.call . "::" . "<")
 (#match? @function.call "^[a-z]")
 (#has-ancestor? @function.call macro_definition) (#set! priority 200))
((token_repetition (identifier) @function.call . "::" . "<")
 (#match? @function.call "^[a-z]")
 (#has-ancestor? @function.call macro_definition) (#set! priority 200))

; Module path prefix: lowercase `name::` (e.g. `tracing::`, `std::`). Lowercase
; guard keeps enum/type paths like `IndexerError::Variant` as a type.
((token_tree (identifier) @module . "::" . (identifier))
 (#match? @module "^[a-z]")
 (#has-ancestor? @module macro_definition) (#set! priority 200))
((token_repetition (identifier) @module . "::" . (identifier))
 (#match? @module "^[a-z]")
 (#has-ancestor? @module macro_definition) (#set! priority 200))

; Path segments by case (heuristic, since macro bodies have no type info):
;   Foo::Bar -> enum type (cyan) :: variant (pink)
;   foo::Bar -> module (silver, rule above) :: type (blue, from main tree)
;   foo::bar -> module (silver) :: function (green)
; `@_x` captures are conditions only (underscore = not highlighted).

; Foo:: -> the CamelCase head before a CamelCase tail is an enum type (cyan).
((token_tree (identifier) @type.enum . "::" . (identifier) @_v)
 (#match? @type.enum "^[A-Z]") (#match? @_v "^[A-Z]")
 (#has-ancestor? @type.enum macro_definition) (#set! priority 200))
((token_repetition (identifier) @type.enum . "::" . (identifier) @_v)
 (#match? @type.enum "^[A-Z]") (#match? @_v "^[A-Z]")
 (#has-ancestor? @type.enum macro_definition) (#set! priority 200))

; ::Bar -> the CamelCase tail after a CamelCase head is a variant (pink).
((token_tree (identifier) @_e . "::" . (identifier) @type.variant)
 (#match? @_e "^[A-Z]") (#match? @type.variant "^[A-Z]")
 (#has-ancestor? @type.variant macro_definition) (#set! priority 200))
((token_repetition (identifier) @_e . "::" . (identifier) @type.variant)
 (#match? @_e "^[A-Z]") (#match? @type.variant "^[A-Z]")
 (#has-ancestor? @type.variant macro_definition) (#set! priority 200))

; foo::bar -> the lowercase tail after a lowercase head is a function (green).
; Priority below module (200) so a mid-path segment (foo::bar::baz) stays silver.
((token_tree (identifier) @_m . "::" . (identifier) @function.call)
 (#match? @_m "^[a-z]") (#match? @function.call "^[a-z]")
 (#has-ancestor? @function.call macro_definition) (#set! priority 199))
((token_repetition (identifier) @_m . "::" . (identifier) @function.call)
 (#match? @_m "^[a-z]") (#match? @function.call "^[a-z]")
 (#has-ancestor? @function.call macro_definition) (#set! priority 199))

; Foo::bar -> CamelCase head stays a type (blue, from main tree); the lowercase
; tail is an associated function / method (green), e.g. `String::from`, `Vec::new`.
((token_tree (identifier) @_t . "::" . (identifier) @function.call)
 (#match? @_t "^[A-Z]") (#match? @function.call "^[a-z]")
 (#has-ancestor? @function.call macro_definition) (#set! priority 199))
((token_repetition (identifier) @_t . "::" . (identifier) @function.call)
 (#match? @_t "^[A-Z]") (#match? @function.call "^[a-z]")
 (#has-ancestor? @function.call macro_definition) (#set! priority 199))

; Std result/option constructors -> variant pink (beats the call rule on `Err(`).
((token_tree (identifier) @type.variant)
 (#any-of? @type.variant "Ok" "Err" "Some" "None")
 (#has-ancestor? @type.variant macro_definition) (#set! priority 201))
((token_repetition (identifier) @type.variant)
 (#any-of? @type.variant "Ok" "Err" "Some" "None")
 (#has-ancestor? @type.variant macro_definition) (#set! priority 201))

; Macro call `name!` (identifier before `!`) -> macro name (brown). Covers bare
; `vec!`/`println!` and path macros `tracing::warn!` (there `tracing` stays a
; module/dark via the rule above). The `!=` operator is a separate token, so
; comparisons like `a != b` are untouched. Highest priority to win the `!` name.
((token_tree (identifier) @macro . "!")
 (#has-ancestor? @macro macro_definition) (#set! priority 202))
((token_repetition (identifier) @macro . "!")
 (#has-ancestor? @macro macro_definition) (#set! priority 202))
