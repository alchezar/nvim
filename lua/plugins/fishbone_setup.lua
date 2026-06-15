-- Toggle to load fishbone from the local dev clone instead of vim.pack; restart after.
local dev = false

if dev then
  vim.opt.runtimepath:prepend('/Users/kinder/Documents/misc/nvim/fishbone.nvim')
end

local theme = require('config.theme_colors')

require('fishbone').setup({
  -- Numbered/plain bookmarks live as extmarks in this namespace (see
  -- custom/bookmarks.lua), not in marks.nvim - point fishbone at it so they
  -- light up the yellow mark layer.
  mark_namespaces = { 'user_bookmarks' },
  colors = {
    cursor     = theme.white,
    search     = theme.purple,
    mark       = theme.yellow,
    selection  = theme.cobalt,
    viewport   = theme.silver,
    error      = theme.red,
    warn       = theme.orange,
    info       = theme.cyan,
    hint       = theme.gray,
    git_add    = theme.green,
    git_change = theme.blue,
    git_delete = theme.red,
    base       = theme.dark,
    divider    = theme.dark,
  },
})
