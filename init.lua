-- Enabling true color terminal allows Neovim to utilize 24-bit RGB color values, 
-- providing a more extensive and accurate range of colors in the termina.
vim.opt.termguicolors = true
-- Font settings. My own font with concinese name.
-- Based on the Iosevka Font. https://typeof.net/Iosevka/
vim.opt.guifont = "Iosevka Chill Nerd:h12"
-- Set color scheme. My own color theme with a concine name. 
-- Based on the MonokaiPro(Spectrum) and OneDarkPro color themes.
vim.cmd("colorscheme kinder_theme")
-- Neovide related settings
vim.g.neovide_window_blurred = true
-- Default clipboard
vim.opt.clipboard = "unnamedplus"
-- Relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true
-- Rounded border for all floating windows
vim.o.winborder = 'rounded'
-- Column guide at 80 characters
vim.opt.colorcolumn = "80"
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
-- Disable search highlight (mapped in keys.lua as <leader>n)
-- Map UA layout
vim.cmd([[
set langmap=йq,цw,уe,кr,еt,нy,гu,шi,щo,зp,х[,ї],фa,іs,вd,аf,пg,рh,оj,лk,дl,ж\\;,є',яz,чx,сc,мv,иb,тn,ьm,б\\,,ю.,ЙQ,ЦW,УE,КR,ЕT,НY,ГU,ШI,ЩO,ЗP,Х{,Ї},ФA,ІS,ВD,АF,ПG,РH,ОJ,ЛK,ДL,Ж:,Є\",ЯZ,ЧX,СC,МV,ИB,ТN,ЬM,Б<,Ю>
]])
-- Plugins
require("plugins")

-- Plugin configs
require("lsp")
require("completion")
require("treesitter")
require("debugging")
require("keys")

-- Plugin setup
require('nvim-autopairs').setup()
require('Comment').setup()
require('gitsigns').setup()
require('todo-comments').setup()
require('trouble').setup()
require('nvim-tree').setup()
require('nvim-web-devicons').setup()
require('virt-column').setup({ char = '▕', virtcolumn = '80' })
