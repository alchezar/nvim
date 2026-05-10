-- nvim-tree: file explorer sidebar
-- Keymaps live in lua/keys.lua (<leader>e/E/f, <D-S-e>)

require('nvim-tree').setup({
  sync_root_with_cwd = true,
  respect_buf_cwd = true,
  view = { width = 40 },
  update_focused_file = {
    enable = true,
    update_root = {
      enable = true,
      ignore_list = {},
    },
  },
  root_dirs = {},
  git = { enable = true },
  filters = {
    git_ignored = false,
  },
  diagnostics = {
    enable = true,
    show_on_dirs = true,
    icons = {
      hint = '●',
      info = '●',
      warning = '●',
      error = '●',
    },
  },
  renderer = {
    highlight_git = 'name',
    highlight_diagnostics = 'name',
    icons = {
      show = { git = false },
    },
  },
})

-- Dim gitignored files in the tree (matches theme `dark`)
local function apply_gitignored_hl()
  local dark = require('theme_colors').dark
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileIgnoredHL', { fg = dark })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderIgnoredHL', { fg = dark })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_gitignored_hl })
apply_gitignored_hl()
