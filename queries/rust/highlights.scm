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
