-- nvim-scrollbar: diagnostic / search / git markers on the right edge
local theme = require('theme_colors')

require('scrollbar').setup({
  handle = {
    color = theme.dark,
  },
  marks = {
    Error = { color = theme.red },
    Warn  = { color = theme.orange },
    Info  = { color = theme.blue },
    Hint  = { color = theme.cyan },
    Misc  = { color = theme.purple },
    Search = { color = theme.yellow },
    -- Git marks pull color from gitsigns highlight groups so the
    -- right-edge scrollbar always matches the left-edge sign column.
    GitAdd    = { highlight = 'GitSignsAdd' },
    GitChange = { highlight = 'GitSignsChange' },
    GitDelete = { highlight = 'GitSignsDelete' },
  },
  excluded_filetypes = {
    'NvimTree', 'startify', 'trouble', 'help', 'dashboard', 'TelescopePrompt',
  },
  handlers = {
    diagnostic = true,
    gitsigns   = true,
    search     = false,
  },
})
