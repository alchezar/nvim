local map = vim.keymap.set
local utils = require('utils')
local builtin = require('telescope.builtin')

-- Leader key
vim.g.mapleader = ' '

-- LSP (matching .ideavimrc bindings)
map('n', 'gd', builtin.lsp_definitions, { desc = 'Go to definition (Telescope)' })
map('n', 'gD', builtin.lsp_type_definitions, { desc = 'Go to type definition (Telescope)' })
map('n', 'gu', builtin.lsp_references, { desc = 'Show usages (Telescope)' })
map('n', 'gi', builtin.lsp_implementations, { desc = 'Show implementations (Telescope)' })
map('n', 'gh', utils.hover, { desc = 'Show hover info' })
map('n', 'gH', vim.lsp.buf.incoming_calls, { desc = 'Call hierarchy' })
map('n', '<leader>rn', vim.lsp.buf.rename, { desc = 'Rename symbol' })
map('n', '<leader>rR', utils.restart_rust_analyzer, { desc = 'Restart rust-analyzer' })
map('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code action' })
map('n', '<leader>o', builtin.lsp_document_symbols, { desc = 'File structure (Telescope)' })
map('n', '[d', vim.diagnostic.goto_prev, { desc = 'Previous diagnostic' })
map('n', ']d', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
map('n', 'go', utils.switch_source_header, { desc = 'Switch C/C++ source/header' })

-- Telescope
map('n', '<Tab>', '<C-^>', { desc = 'Switch to alternate file' })
map('n', '<C-Tab>', builtin.oldfiles, { desc = 'Recent files' })
map('n', '<D-e>', builtin.buffers, { desc = 'Open buffers' })
map('n', '<C-p>', builtin.find_files, { desc = 'Find files' })
map('n', '<leader>ff', builtin.find_files, { desc = 'Find files (fuzzy)' })
map('n', '<leader>fg', builtin.live_grep, { desc = 'Live grep' })
map('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
map('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
map('n', '<leader>fk', builtin.keymaps,   { desc = 'Search keymaps' })
map('n', '<leader>?',  builtin.keymaps,   { desc = 'Search keymaps (cheatsheet)' })
map('n', '<leader>fp', utils.open_clipboard_path, { desc = 'Open file path from clipboard' })
map('n', '<leader>fa', function()
  builtin.find_files({ cwd = vim.env.HOME, hidden = true, no_ignore = true, prompt_title = 'Find files ($HOME)' })
end, { desc = 'Find files everywhere ($HOME)' })

-- Copy file path / location to system clipboard
local function yank_to_clipboard(text)
  vim.fn.setreg('+', text)
  vim.notify('Copied: ' .. text)
end
map('n', '<leader>cp', function() yank_to_clipboard(vim.fn.expand('%') .. ':' .. vim.fn.line('.')) end,   { desc = 'Copy relative path:line' })
map('n', '<leader>cP', function() yank_to_clipboard(vim.fn.expand('%:p') .. ':' .. vim.fn.line('.')) end, { desc = 'Copy absolute path:line' })
map('n', '<leader>cf', function() yank_to_clipboard(vim.fn.expand('%:t') .. ':' .. vim.fn.line('.')) end, { desc = 'Copy filename:line' })
map('n', '<leader>cr', function() yank_to_clipboard(vim.fn.expand('%')) end, { desc = 'Copy relative path' })

-- Nvim-tree
map('n', '<D-S-e>', ':NvimTreeFindFileToggle<CR>', { desc = 'Toggle file tree (reveal current file)', silent = true })
map('n', '<leader>E', ':NvimTreeFindFileToggle<CR>', { desc = 'Toggle file tree (reveal current file)', silent = true })
map('n', '<leader>e', ':NvimTreeFocus<CR>', { desc = 'Focus file tree', silent = true })
map('n', '<leader>f', ':NvimTreeFindFile<CR>', { desc = 'Find file in tree', silent = true })

-- Trouble
map('n', '<leader>xx', ':Trouble diagnostics toggle<CR>', { desc = 'Diagnostics', silent = true })

-- Git
map('n', '<leader>gb', ':BlameToggle<CR>', { desc = 'Toggle git blame side panel (date heat-map)', silent = true })
map('n', '<leader>gp', ':Gitsigns preview_hunk<CR>', { desc = 'Preview hunk diff (popup)', silent = true })
map('n', '<leader>gm', ':DiffviewOpen<CR>',          { desc = 'Open diffview (3-way merge / diff)', silent = true })
map('n', '<leader>gM', ':DiffviewClose<CR>',         { desc = 'Close diffview',                    silent = true })
map('n', '<leader>gh', ':DiffviewFileHistory %<CR>', { desc = 'File history (current file)',       silent = true })

-- Database (vim-dadbod-ui)
map('n', '<leader>du', ':DBUIToggle<CR>',       { desc = 'Toggle DB UI sidebar', silent = true })
map('n', '<leader>df', ':DBUIFindBuffer<CR>',   { desc = 'Find DB buffer',       silent = true })
map('n', '<leader>dr', ':DBUIRenameBuffer<CR>', { desc = 'Rename DB buffer',     silent = true })
map('n', '<leader>dq', ':DBUILastQueryInfo<CR>',{ desc = 'Last query info',      silent = true })

-- Startify dashboard
map('n', 'gq', ':Startify<CR>', { desc = 'Open Startify', silent = true })
-- Format current buffer (Opt+Shift+F)
map({ 'n', 'v' }, '<M-S-f>', utils.format, { desc = 'Format buffer' })
-- Q -> gq: format / re-wrap text and comments using `textwidth`
map({ 'n', 'x' }, 'Q', 'gq', { desc = 'Format text (wrap at textwidth)' })
-- Disable search highlight
map('n', '<leader>n', ':noh<CR>', { desc = 'Clear search highlight', silent = true })
-- Insert new line above/below without entering insert mode
map('n', '<S-Enter>', 'moO<Esc>jw', { desc = 'New line above' })
map('n', '<C-Enter>', 'moo<Esc>kw', { desc = 'New line below' })
-- Keep register on paste
map('n', '<leader>p', '"_dP', { desc = 'Paste without overwriting register' })
-- Search selected text
map('v', '*', 'y/<C-R>"<CR>', { desc = 'Search selected text' })
-- Open yazi file manager
map('n', '<leader>y', utils.open_yazi, { desc = 'Open yazi' })
-- Toggle inlay hints
map('n', '<D-C-]>', utils.toggle_inlay_hints,   { desc = 'Toggle inlay hints' })
map('n', '<leader>i', utils.toggle_inlay_hints, { desc = 'Toggle inlay hints' })

-- DAP (debug)
local dap = function(action) return function() require('dap')[action]() end end
map('n', '<F5>', dap('continue'), { desc = 'Debug: continue' })
map('n', '<F10>', dap('step_over'), { desc = 'Debug: step over' })
map('n', '<F11>', dap('step_into'), { desc = 'Debug: step into' })
map('n', '<F12>', dap('step_out'), { desc = 'Debug: step out' })
map('n', '<leader>b', dap('toggle_breakpoint'), { desc = 'Toggle breakpoint' })
