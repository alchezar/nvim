local map = vim.keymap.set
local utils = require('config.utils')
local builtin = require('telescope.builtin')
local translate = require('plugins.translate_setup')
local dap = function(action) return function() require('dap')[action]() end end

vim.g.mapleader = ' ';                                                                                                 -- Leader key
map('n', 'gq', ':Startify<CR>', { desc = 'Open Startify', silent = true })                                             -- Startify dashboard
map({ 'n', 'v' }, '<M-S-f>', utils.format, { desc = 'Format buffer' })                                                 -- Format current buffer (Opt+Shift+F)
map({ 'n', 'x' }, 'Q', 'gq', { desc = 'Format text (wrap at textwidth)' })                                             -- Q -> gq: format / re-wrap text and comments using `textwidth`
map('n', '<M-z>', '<Cmd>set wrap!<CR>', { desc = 'Toggle line wrap' })                                                 -- Toggle line wrap
map('n', '<S-Enter>', 'moO<Esc>jw', { desc = 'New line above' })                                                       -- Insert new line above without entering insert mode
map('n', '<C-Enter>', 'moo<Esc>kw', { desc = 'New line below' })                                                       -- Insert new line below without entering insert mode
map('x', '*', function() utils.search_visual(true) end, { desc = 'Search selected text forward' })                     -- Search selected text forward
map('x', '#', function() utils.search_visual(false) end, { desc = 'Search selected text backward' })                   -- Search selected text backward
map('n', '<D-C-]>', utils.toggle_inlay_hints, { desc = 'Toggle inlay hints' })                                         -- Toggle inlay hints
map('n', '<D-/>', 'gccj', { desc = 'Toggle comment on current line (Cmd+/)', remap = true })                           -- Toggle line comment (Cmd+/) in normal mode
map('x', '<D-/>', "gc'>j", { desc = 'Toggle comment on selection (Cmd+/)', remap = true })                             -- Toggle line comment (Cmd+/) in visual mode
map('x', '<D-C-u>', function() translate.translate_selection('UK') end, { desc = 'Translate selection to Ukrainian' }) -- Translate selected text (Cmd+Ctrl+U: -> Ukrainian)
map('x', '<D-C-S-u>', function() translate.translate_selection('EN') end, { desc = 'Translate selection to English' }) -- Translate selected text (Cmd+Ctrl+Shift+U: -> English)
map('n', '<leader>n', ':noh<CR>', { desc = 'Clear search highlight', silent = true })                                  -- Disable search highlight
map('n', '<leader>sm', ':messages<CR>', { desc = 'Show :messages' })                                                   -- Show :messages output
map('n', '<leader>sl', [[/\vlet (mut )?\w*:<CR>]], { desc = 'Search let/let mut bindings' })                           -- Highlight Rust let / let mut declarations
map('n', '<leader>p', '"_dP', { desc = 'Paste without overwriting register' })                                         -- Keep register on paste
map('n', '<leader>y', utils.open_yazi, { desc = 'Open yazi' })                                                         -- Open yazi file manager
map('n', '<leader>i', utils.toggle_inlay_hints, { desc = 'Toggle inlay hints' })                                       -- Toggle inlay hints
map('n', '<leader>wf', utils.focus_floating, { desc = 'Focus floating window (toggle)' })                              -- Focus floating window (toggle)
map('n', '<leader>wh', '<C-w>h', { desc = 'Go to window left', silent = true })                                        -- Window left
map('n', '<leader>wj', '<C-w>j', { desc = 'Go to window below', silent = true })                                       -- Window below
map('n', '<leader>wk', '<C-w>k', { desc = 'Go to window above', silent = true })                                       -- Window above
map('n', '<leader>wl', '<C-w>l', { desc = 'Go to window right', silent = true })                                       -- Window right
map('n', '<leader>xx', ':Trouble diagnostics toggle<CR>', { desc = 'Diagnostics', silent = true })                     -- Trouble
-- LSP (matching .ideavimrc bindings)
map('n', 'gd', builtin.lsp_definitions, { desc = 'Go to definition (Telescope)' })
map('n', 'gD', builtin.lsp_type_definitions, { desc = 'Go to type definition (Telescope)' })
map('n', 'gu', builtin.lsp_references, { desc = 'Show usages (Telescope)' })
map('n', 'gi', builtin.lsp_implementations, { desc = 'Show implementations (Telescope)' })
map('n', 'gI', utils.go_to_interface, { desc = 'Go to trait/interface method (parent of impl)' })
map('n', 'gh', utils.hover, { desc = 'Show hover info' })
map('n', 'gH', vim.lsp.buf.incoming_calls, { desc = 'Call hierarchy' })
map({ 'n', 'x' }, '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code action' })
map({ 'n', 'x' }, '<D-.>', vim.lsp.buf.code_action, { desc = 'Code action (Cmd+.)' })
map({ 'n', 'x' }, '<C-.>', vim.lsp.buf.code_action, { desc = 'Code action (Ctrl+.)' })
map('n', '[d', utils.diagnostic_prev, { desc = 'Previous diagnostic' })
map('n', ']d', utils.diagnostic_next, { desc = 'Next diagnostic' })
map('n', 'go', utils.switch_source_header, { desc = 'Switch C/C++ source/header' })
map('n', '<leader>o', builtin.lsp_document_symbols, { desc = 'File structure (Telescope)' })
map('n', '<leader>rn', vim.lsp.buf.rename, { desc = 'Rename symbol' })
map('n', '<leader>rl', utils.restart_buf_lsp, { desc = 'Reload LSP for current buffer' })
map('n', '<leader>rb', utils.reload_buf, { desc = 'Reload current buffer (wipe and reopen)' })
-- Telescope
map('n', '<Tab>', '<C-^>', { desc = 'Switch to alternate file' })
map('n', '<C-Tab>', builtin.oldfiles, { desc = 'Recent files' })
map('n', '<D-e>', function() builtin.buffers({ sort_mru = true, ignore_current_buffer = true }) end,
  { desc = 'Open buffers (MRU)' })
map('n', '<C-p>', builtin.find_files, { desc = 'Find files' })
map('n', '<leader>ff', builtin.find_files, { desc = 'Find files (fuzzy)' })
-- no regex so (), [],... need no escaping
map('n', '<leader>fg',
  function() builtin.live_grep({ additional_args = function() return { '--fixed-strings' } end }) end,
  { desc = 'Live grep (literal)' })
map('n', '<leader>fG', builtin.live_grep, { desc = 'Live grep' })
map('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
map('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
map('n', '<leader>fk', builtin.keymaps, { desc = 'Search keymaps' })
map('n', '<leader>?', builtin.keymaps, { desc = 'Search keymaps (cheatsheet)' })
map('n', '<leader>fp', utils.open_clipboard_path, { desc = 'Open file path from clipboard' })
map('n', '<leader>fa', utils.find_files_in_home, { desc = 'Find files everywhere ($HOME)' })
map('n', '<leader>fe', ':AxumRoutes<CR>', { desc = 'Axum/utoipa endpoints', silent = true })
map('n', '<leader>fE', ':AxumRoutesFile<CR>', { desc = 'Axum/utoipa endpoints (file)', silent = true })
map('n', '<leader>fr', function() builtin.oldfiles({ cwd_only = true }) end, { desc = 'Recent files (project)' })
map('n', '<leader>fR', builtin.oldfiles, { desc = 'Recent files' })
-- Copy file path / location to system clipboard
map('n', '<leader>cp', function() utils.yank_to_clipboard(vim.fn.expand('%') .. ':' .. vim.fn.line('.')) end,
  { desc = 'Copy relative path:line' })
map('n', '<leader>cP', function() utils.yank_to_clipboard(vim.fn.expand('%:p') .. ':' .. vim.fn.line('.')) end,
  { desc = 'Copy absolute path:line' })
map('n', '<leader>cf', function() utils.yank_to_clipboard(vim.fn.expand('%:t') .. ':' .. vim.fn.line('.')) end,
  { desc = 'Copy filename:line' })
map('n', '<leader>cr', function() utils.yank_to_clipboard(vim.fn.expand('%')) end, { desc = 'Copy relative path' })
-- Nvim-tree
map('n', '<D-S-e>', ':NvimTreeFindFileToggle<CR>', { desc = 'Toggle file tree (reveal current file)', silent = true })
map('n', '<leader>E', ':NvimTreeFindFileToggle<CR>', { desc = 'Toggle file tree (reveal current file)', silent = true })
map('n', '<leader>e', ':NvimTreeFocus<CR>', { desc = 'Focus file tree', silent = true })
map('n', '<leader>f', ':NvimTreeFindFile<CR>', { desc = 'Find file in tree', silent = true })
-- Git
map('n', '<leader>gs', builtin.git_status, { desc = 'Git status (changed files)' })
map('n', '<leader>gb', ':BlameToggle<CR>', { desc = 'Toggle git blame side panel (date heat-map)', silent = true })
map('n', '<leader>gp', utils.gitsigns_preview_hunk, { desc = 'Preview hunk diff (popup)' })
map('n', '<leader>gr', function()
  require('gitsigns').reset_hunk(); vim.cmd('noautocmd write')
end, { desc = 'Reset hunk under cursor and save (no autoformat)' })
map({ 'n', 'x' }, '<leader>ga', ':Gitsigns stage_hunk<CR>', { desc = 'Stage hunk or selected lines', silent = true })
map('n', '<leader>gm', ':DiffviewOpen<CR>', { desc = 'Open diffview (3-way merge / diff)', silent = true })
map('n', '<leader>gc', ':DiffviewClose<CR>', { desc = 'Close diffview', silent = true })
map('n', '<leader>gh', ':DiffviewFileHistory %<CR>', { desc = 'File history (current file)', silent = true })
map('n', '<leader>gv', utils.branch_review_toggle,
  { desc = 'Toggle branch review (count = last N commits, else whole branch)' })
map('n', '<leader>gl', utils.open_lazygit, { desc = 'Open lazygit (floating)', silent = true })
-- Database (nvim-dbee). DBUIOpen is the wrapper that reloads .env first.
map('n', '<leader>du', ':DBUIOpen<CR>', { desc = 'Toggle Dbee UI (reload .env)', silent = true })
map('n', '<leader>de', function() require('plugins.dbee').show_editor() end,
  { desc = 'Dbee: show editor float', silent = true })
map({ 'n', 'x' }, '<leader>dr', utils.dbee_run, { desc = 'Dbee: run selection / under cursor', silent = true })
map('n', '<leader>df', function() require('dbee').api.ui.drawer_show() end,
  { desc = 'Dbee: focus drawer', silent = true })
map('n', '<leader>dq', function() require('plugins.dbee').show_call_log() end,
  { desc = 'Dbee: show call log', silent = true })
-- DAP (debug)
map('n', '<F5>', dap('continue'), { desc = 'Debug: continue' })
map('n', '<F10>', dap('step_over'), { desc = 'Debug: step over' })
map('n', '<F11>', dap('step_into'), { desc = 'Debug: step into' })
map('n', '<F12>', dap('step_out'), { desc = 'Debug: step out' })
map('n', '<leader>b', dap('toggle_breakpoint'), { desc = 'Toggle breakpoint' })
