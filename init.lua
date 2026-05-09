-- Enabling true color terminal allows Neovim to utilize 24-bit RGB color values,
-- providing a more extensive and accurate range of colors in the termina.
vim.opt.termguicolors = true
-- Font settings. My own font with concinese name.
-- Based on the Iosevka Font. https://typeof.net/Iosevka/
vim.opt.guifont = "Iosevka Chill Nerd:h12"
-- Set color scheme. My own color theme with a concine name.
-- Based on the MonokaiPro(Spectrum) and OneDarkPro color themes.
vim.cmd("colorscheme kinder_theme")
-- Default clipboard
vim.opt.clipboard = "unnamedplus"
-- Relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true
-- Rounded border for all floating windows
vim.o.winborder = 'rounded'
-- Column guide at 80 characters
vim.opt.colorcolumn = "80"
-- Tabs / indent settings
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true
-- Case-insensitive search; uppercase in pattern -> case-sensitive (smartcase)
vim.opt.ignorecase = true
vim.opt.smartcase = true
-- Whitespace display: trailing dots always; full whitespace in visual mode
vim.opt.list = true
vim.opt.listchars = { trail = '·', tab = '  ' }
vim.api.nvim_create_autocmd('ModeChanged', {
    callback = function()
        if vim.v.event.new_mode:match('^[vV\22]') then
            vim.opt.listchars = { trail = '·', space = '·', tab = '→ ', leadmultispace = '│···' }
        else
            vim.opt.listchars = { trail = '·', tab = '  ' }
        end
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
require("neovide")

-- Plugins
require("plugins")

-- Plugin configs
require("lsp")
require("completion")
require("treesitter")
require("debugging")
require("formatting")
require("keys")

-- Plugin setup
require('nvim-autopairs').setup()
require('Comment').setup()
require('gitsigns').setup()
require('todo-comments').setup()
require('trouble').setup()
require('file-tree')

-- Auto-cd to project root based on common markers
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function(args)
    require('utils').auto_cd_to_project_root(args.buf)
  end,
})
require('nvim-web-devicons').setup()
require('virt-column').setup({ char = '▕', virtcolumn = '80' })
require('bookmarks')
require('markdown')
require('scrollbar_setup')

-- EasyMotion (matches .ideavimrc binding: s = bidirectional 2-char search)
vim.g.EasyMotion_smartcase = 1
vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(easymotion-s2)')
