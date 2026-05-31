require('nvim-autopairs').setup({ enable_check_bracket_line = false })

-- Auto-close generics `<>` in Rust after a type name; skips comparison like `a < b`.
local Rule = require('nvim-autopairs.rule')
local cond = require('nvim-autopairs.conds')
require('nvim-autopairs').add_rules({
  Rule('<', '>', { 'rust' })
      :with_pair(cond.before_regex('[%w_:]$'))
      :with_move(function(opts) return opts.char == '>' end),
})
