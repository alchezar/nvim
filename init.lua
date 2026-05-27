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
-- Blank out vertical split separators (between editor splits, nvim-tree, dbui).
vim.opt.fillchars:append({ vert = ' ' })
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
vim.api.nvim_set_hl(0, "StatusLine", { bg = "NONE", fg = "#a0a0a0" })
vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "NONE", fg = "#606060" })
-- Move the current line up/down
vim.api.nvim_set_keymap('n', '<C-k>', ":m .-2<Enter>", { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<C-j>', ":m .+1<Enter>", { noremap = true, silent = true })
-- Move selected lines up/down
vim.api.nvim_set_keymap('v', '<C-k>', ":m '<-2<CR>gv", { noremap = true, silent = true })
vim.api.nvim_set_keymap('v', '<C-j>', ":m '>+1<CR>gv", { noremap = true, silent = true })

-- Vim UI2
require ('vim._core.ui2').enable({
  enable = true,
  msg = {
    target = "cmd",
    pager = { height = 0.5 },
    dialog = { height = 0.5 },
    cmd = { height = 0.5 },
    msg = { height = 0.5, timeout = 4500 },
  },
})

-- Neovide related settings
require("config.neovide")

-- Multi-cursor (vim-visual-multi) - must be set before plugins load
vim.g.VM_maps = {
  ['Add Cursor Down']    = '<D-M-Down>',
  ['Add Cursor Up']      = '<D-M-Up>',
  ['Find Under']         = '<D-d>',
  ['Find Subword Under'] = '<D-d>',
  ['Switch Mode']        = 'v',
}
vim.g.VM_silent_exit = 1
vim.g.VM_set_statusline = 0
vim.g.VM_show_warnings = 0

-- vim-visual-multi cursor colors: white block cursors, theme-matched selection
local function apply_vm_hl()
  local theme = require('config.theme_colors')
  vim.api.nvim_set_hl(0, 'VM_Mono',   { fg = theme.bg, bg = theme.white })
  vim.api.nvim_set_hl(0, 'VM_Cursor', { fg = theme.bg, bg = theme.white })
  vim.api.nvim_set_hl(0, 'VM_Insert', { fg = theme.bg, bg = theme.white })
  vim.api.nvim_set_hl(0, 'VM_Extend', { bg = theme.dark })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_vm_hl })
apply_vm_hl()

-- Plugins
require("config.plugins")

-- Plugin configs
require("config.autosave")
require("config.keys")
require("plugins.telescope_setup")
require("plugins.lsp")
require("plugins.completion_setup")
require("plugins.treesitter")
require("plugins.debugging")
require("plugins.formatting")
require("plugins.translate_setup")
require("plugins.axum_routes")

-- Plugin setup
require('nvim-autopairs').setup({ enable_check_bracket_line = false })
-- Auto-close generics `<>` in Rust after a type name; skips comparison like `a < b`.
do
  local Rule = require('nvim-autopairs.rule')
  local cond = require('nvim-autopairs.conds')
  require('nvim-autopairs').add_rules({
    Rule('<', '>', { 'rust' })
      :with_pair(cond.before_regex('[%w_:]$'))
      :with_move(function(opts) return opts.char == '>' end),
  })
end
require('Comment').setup()
require('gitsigns').setup()
require('todo-comments').setup()
require('trouble').setup()
require('plugins.file-tree')

-- Auto-cd to project root based on common markers. nested = true so the global cd's
-- DirChanged reaches nvim-tree (sync_root_with_cwd), re-rooting the tree on project change.
vim.api.nvim_create_autocmd('BufEnter', {
  nested = true,
  callback = function(args)
    require('config.utils').auto_cd_to_project_root(args.buf)
  end,
})
require('config.tree_icons').setup()
require('virt-column').setup({ enabled = false, char = '▕', virtcolumn = '80,100', highlight = 'VirtColumn' })
require('nvim-highlight-colors').setup({ render = 'background' })
require('plugins.bookmarks')
require('plugins.markdown')
require('plugins.fishbone_setup')
require('plugins.dbee')
require('plugins.blame_setup')
require('plugins.diffview_setup')
require('plugins.startify_setup')
require('crates').setup({ popup = { border = 'rounded' } })
require('plugins.hex_setup')

-- In Cargo.toml, override `gh` to show the crate popup instead of LSP hover.
vim.api.nvim_create_autocmd('BufRead', {
  pattern = 'Cargo.toml',
  callback = function(args)
    vim.keymap.set('n', 'gh', require('crates').show_popup,
      { buffer = args.buf, desc = 'Show crate popup' })
  end,
})

-- EasyMotion (matches .ideavimrc binding: s = bidirectional 2-char search)
vim.g.EasyMotion_smartcase = 1
vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(easymotion-s2)')
