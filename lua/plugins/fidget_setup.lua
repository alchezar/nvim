-- Lighter bg for the fidget float (it can't be transparent in Neovide), so it
-- contrasts less with the see-through editor. Own group, not the theme palette.
vim.api.nvim_set_hl(0, 'FidgetNormal', { bg = '#333333' })

require('fidget').setup({
  -- String (not table) icon = no spinner animation.
  progress = { display = { progress_icon = '' } },
  notification = { window = { border = 'rounded', normal_hl = 'FidgetNormal' } },
})
