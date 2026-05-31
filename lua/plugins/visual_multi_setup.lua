-- vim-visual-multi. Globals must be set before the plugin loads.
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

-- Cursor colors: white block cursors, theme-matched selection.
local function apply_vm_hl()
  local theme = require('config.theme_colors')
  vim.api.nvim_set_hl(0, 'VM_Mono', { fg = theme.bg, bg = theme.white })
  vim.api.nvim_set_hl(0, 'VM_Cursor', { fg = theme.bg, bg = theme.white })
  vim.api.nvim_set_hl(0, 'VM_Insert', { fg = theme.bg, bg = theme.white })
  vim.api.nvim_set_hl(0, 'VM_Extend', { bg = theme.dark })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_vm_hl })
apply_vm_hl()
