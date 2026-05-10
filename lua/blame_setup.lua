-- blame.nvim: side-panel git blame with date heat-map.
-- Recent commits are warm (red), older commits are cool (purple).
-- Open via <leader>gb (mapped in keys.lua, replaces :Gitsigns blame).

local theme = require('theme_colors')

require('blame').setup({
  date_format = '%Y-%m-%d',
  merge_consecutive = false,
  max_summary_width = 30,
  -- Heat-map: index 0 = oldest, last index = newest (blame.nvim convention).
  -- We want recent = warm, old = cool, so the array goes purple -> red.
  colors = {
    theme.purple,
    theme.blue,
    theme.cyan,
    theme.green,
    theme.yellow,
    theme.orange,
    theme.red,
  },
  blame_options = nil,  -- pass extra `git blame` flags here if needed
  commit_detail_view = 'vsplit',
  format_fn = nil,
  mappings = {
    commit_info = 'i',
    stack_push  = '<TAB>',
    stack_pop   = '<BS>',
    show_commit = '<CR>',
    close       = { '<Esc>', 'q' },
  },
})
