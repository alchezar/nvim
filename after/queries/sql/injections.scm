; extends

; PL/pgSQL bodies in $$...$$ that the sql grammar can't parse collapse into ERROR
; nodes with no captures (grey text). Re-inject each ERROR zone as sql so its
; keywords/strings/numbers/calls highlight. Scoped to function_body: never touches
; DROP-arg ERRORs or the $$ delimiters, so no self-recursion.
((function_body (ERROR) @injection.content)
 (#set! injection.language "sql"))
