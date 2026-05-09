-- nvim-tree: file explorer sidebar
-- Keymaps live in lua/keys.lua (<leader>e/E/f, <D-S-e>)

require('nvim-tree').setup({
  sync_root_with_cwd = true,
  respect_buf_cwd = true,
  update_focused_file = {
    enable = true,
    update_root = {
      enable = true,
      ignore_list = {},
    },
  },
  root_dirs = {},
  git = { enable = true },
  renderer = {
    highlight_git = 'name',
    icons = {
      show = { git = false },
    },
  },
})
