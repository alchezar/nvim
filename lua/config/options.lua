local colors = require('config.theme_colors')

vim.opt.termguicolors = true
vim.opt.guifont = "Iosevka Chill Nerd:h12"
vim.cmd("colorscheme kinder_theme")
vim.opt.clipboard = "unnamedplus"
vim.o.winborder = 'rounded'
-- Relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true
-- Force 80 even when bundled ftplugins (e.g. rust.vim sets 100) override it.
vim.opt.textwidth = 80
vim.api.nvim_create_autocmd('FileType', {
  callback = function() vim.opt_local.textwidth = 80 end,
})
vim.opt.scrolloff = 2
-- Tabs / indent settings
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true
-- Case-insensitive search; uppercase in pattern -> case-sensitive (smartcase)
vim.opt.ignorecase = true
vim.opt.smartcase = true
-- Whitespace display: trailing dots always; full whitespace in visual/insert modes
vim.opt.list = true
vim.opt.listchars = { trail = '·', tab = '  ' }
-- Blank out split separators (between editor splits, nvim-tree, dbui) - both directions.
vim.opt.fillchars:append({
  vert = ' ',
  horiz = ' ',
  horizup = ' ',
  horizdown = ' ',
  vertleft = ' ',
  vertright = ' ',
  verthoriz = ' ',
})
vim.api.nvim_create_autocmd('ModeChanged', {
  callback = function()
    local mode = vim.v.event.new_mode
    local show_all = mode:match('^[vV\22]') ~= nil or mode:match('^[iR]') ~= nil
    if show_all then
      local sw = vim.bo.shiftwidth
      if sw <= 0 then sw = vim.bo.tabstop end
      local lead = '│' .. string.rep('·', math.max(sw - 1, 0))
      vim.opt.listchars = { trail = '·', space = '·', tab = '→ ', leadmultispace = lead }
    else
      vim.opt.listchars = { trail = '·', tab = '  ' }
    end
    local ok, vc = pcall(require, 'virt-column')
    if ok then vc.update({ enabled = show_all }) end
  end,
})
-- Apply tab_spaces from rustfmt.toml to *.rs buffers
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'rust',
  callback = function(args)
    require('config.utils').apply_rustfmt_indent(args.buf)
  end,
})
-- Visual lines move (for lines longer than terminal width)
vim.keymap.set('n', 'j', 'gj')
vim.keymap.set('n', 'k', 'gk')
-- Transparent background
vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
-- Transparent status line
vim.api.nvim_set_hl(0, "StatusLine", { bg = "NONE", fg = colors.gray })
vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "NONE", fg = colors.dark })
-- Move the current line up/down
vim.api.nvim_set_keymap('n', '<C-k>', ":m .-2<Enter>", { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<C-j>', ":m .+1<Enter>", { noremap = true, silent = true })
-- Move selected lines up/down
vim.api.nvim_set_keymap('v', '<C-k>', ":m '<-2<CR>gv", { noremap = true, silent = true })
vim.api.nvim_set_keymap('v', '<C-j>', ":m '>+1<CR>gv", { noremap = true, silent = true })

-- Vim UI2
require('vim._core.ui2').enable({
  enable = true,
  msg = {
    target = "cmd",
    pager = { height = 0.5 },
    dialog = { height = 0.5 },
    cmd = { height = 0.5 },
    msg = { height = 0.5, timeout = 4500 },
  },
})
