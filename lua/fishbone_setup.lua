-- Set to `true` to load fishbone from the local dev clone instead of the
-- version installed by `vim.pack`. Restart Neovim after toggling.
local dev = false

if dev then
  vim.opt.runtimepath:prepend('/Users/kinder/Documents/misc/nvim/fishbone.nvim')
end

local theme = require('theme_colors')

require('fishbone').setup({
  colors = {
    cursor     = theme.white,
    search     = theme.pink,
    mark       = theme.yellow,
    viewport   = theme.silver,
    error      = theme.red,
    warn       = theme.orange,
    info       = theme.cyan,
    hint       = theme.purple,
    git_add    = theme.green,
    git_change = theme.blue,
    git_delete = theme.red,
    base       = theme.dark,
  },
})
