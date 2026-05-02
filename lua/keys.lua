local map = vim.keymap.set

-- Leader key
vim.g.mapleader = ' '

-- LSP (matching .ideavimrc bindings)
map('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to declaration' })
map('n', 'gu', vim.lsp.buf.references, { desc = 'Show usages' })
map('n', 'gI', vim.lsp.buf.implementation, { desc = 'Quick implementations' })
map('n', 'gi', vim.lsp.buf.implementation, { desc = 'Go to implementation' })
map('n', 'gh', function() vim.lsp.buf.hover({ max_width = 80 }) end, { desc = 'Show hover info' })
map('n', 'gH', vim.lsp.buf.incoming_calls, { desc = 'Call hierarchy' })
map('n', '<leader>rn', vim.lsp.buf.rename, { desc = 'Rename symbol' })
map('n', '<leader>ca', vim.lsp.buf.code_action, { desc = 'Code action' })
map('n', '<leader>o', vim.lsp.buf.document_symbol, { desc = 'File structure' })
map('n', '[d', vim.diagnostic.goto_prev, { desc = 'Previous diagnostic' })
map('n', ']d', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })

-- Telescope
local builtin = require('telescope.builtin')
map('n', '<C-Tab>', builtin.oldfiles, { desc = 'Recent files' })
map('n', '<D-e>', builtin.buffers, { desc = 'Open buffers' })
map('n', '<C-p>', builtin.find_files, { desc = 'Find files' })
map('n', '<leader>fg', builtin.live_grep, { desc = 'Live grep' })
map('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
map('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })

-- Nvim-tree (matching .ideavimrc NERDTree bindings)
map('n', '<leader>e', ':NvimTreeToggle<CR>', { desc = 'Toggle file tree', silent = true })
map('n', '<leader>f', ':NvimTreeFindFile<CR>', { desc = 'Find file in tree', silent = true })

-- Trouble
map('n', '<leader>xx', ':Trouble diagnostics toggle<CR>', { desc = 'Diagnostics', silent = true })

-- Startify dashboard
map('n', 'gq', ':Startify<CR>', { desc = 'Open Startify', silent = true })

-- Format current buffer (Opt+Shift+F)
map({ 'n', 'v' }, '<M-S-f>', function() require('conform').format({ async = true, lsp_format = 'fallback' }) end, { desc = 'Format buffer' })

-- Disable search highlight
map('n', '<leader>n', ':noh<CR>', { desc = 'Clear search highlight', silent = true })

-- Insert new line above/below without entering insert mode
map('n', '<S-Enter>', 'moO<Esc>jw', { desc = 'New line above' })
map('n', '<C-Enter>', 'moo<Esc>kw', { desc = 'New line below' })

-- Keep register on paste
map('n', '<leader>p', '"_dP', { desc = 'Paste without overwriting register' })

-- Search selected text
map('v', '*', 'y/<C-R>"<CR>', { desc = 'Search selected text' })

-- DAP (debug)
map('n', '<F5>', function() require('dap').continue() end, { desc = 'Debug: continue' })
map('n', '<F10>', function() require('dap').step_over() end, { desc = 'Debug: step over' })
map('n', '<F11>', function() require('dap').step_into() end, { desc = 'Debug: step into' })
map('n', '<F12>', function() require('dap').step_out() end, { desc = 'Debug: step out' })
map('n', '<leader>b', function() require('dap').toggle_breakpoint() end, { desc = 'Toggle breakpoint' })

-- Open yazi file manager
map('n', '<leader>y', function()
  local tmp = vim.fn.tempname()
  vim.cmd('silent !yazi --chooser-file=' .. tmp)
  vim.cmd('redraw!')
  local f = io.open(tmp, 'r')
  if f then
    local path = f:read('*l')
    f:close()
    os.remove(tmp)
    if path and path ~= '' then
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
    end
  end
end, { desc = 'Open yazi' })

-- Toggle inlay hints
map('n', '<D-C-]>', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end, { desc = 'Toggle inlay hints' })
map('n', '<leader>i', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end, { desc = 'Toggle inlay hints' })

-- Comment.nvim (gcc / gc in visual - works out of the box)
