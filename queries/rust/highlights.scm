; extends

; Force comment color to win over markdown/rustdoc injection
; (priority > default 100 makes @comment.rust override injected captures)
((line_comment) @comment.rust (#set! priority 110))
((block_comment) @comment.rust (#set! priority 110))
