-- EasyMotion (matches .ideavimrc binding: s = bidirectional 2-char search)
vim.g.EasyMotion_smartcase = 1
vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(easymotion-s2)')

-- Pause diagnostics and gitsigns while EasyMotion rewrites the buffer with hint
-- labels, otherwise both decorate the temporarily mangled text and flicker.
local easymotion_grp = vim.api.nvim_create_augroup('EasyMotionDiagnostics', { clear = true })
vim.api.nvim_create_autocmd('User', {
  group = easymotion_grp,
  pattern = 'EasyMotionPromptBegin',
  callback = function()
    vim.diagnostic.enable(false)
    require('gitsigns').toggle_signs(false)
  end,
})
vim.api.nvim_create_autocmd('User', {
  group = easymotion_grp,
  pattern = 'EasyMotionPromptEnd',
  callback = function()
    vim.diagnostic.enable(true)
    require('gitsigns').toggle_signs(true)
  end,
})
