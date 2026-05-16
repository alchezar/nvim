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
      padding = '  ',
      show = { git = false },
      glyphs = {
        folder = {
          default    = '\u{F07B}',  -- nf-fa-folder (closed, filled) for non-empty
          open       = '\u{F115}',  -- nf-fa-folder_open_o (matches yazi theme)
          empty      = '\u{F114}',  -- nf-fa-folder_o (outline) for empty closed
          empty_open = '\u{F115}',
        },
      },
    },
  },
})

-- Tree highlight overrides: dim gitignored items, neutral gray for folders.
local function apply_tree_hl()
  local theme = require('theme_colors')
  -- Gitignored stays a darker gray
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileIgnoredHL',   { fg = theme.dark })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderIgnoredHL', { fg = theme.dark })
  -- Modified (dirty) git files/folders -> blue (matches GitSignsChange)
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileDirtyHL',     { fg = theme.blue })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderDirtyHL',   { fg = theme.blue })
  -- Folders neutral gray (was theme blue by default)
  vim.api.nvim_set_hl(0, 'NvimTreeFolderName',        { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'NvimTreeOpenedFolderName',  { fg = theme.gray, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTreeEmptyFolderName',   { fg = theme.gray, italic = true })
  vim.api.nvim_set_hl(0, 'NvimTreeFolderIcon',        { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'NvimTreeOpenedFolderIcon',  { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'NvimTreeRootFolder',        { fg = theme.gray, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTreeSymlinkFolderName', { fg = theme.gray, italic = true })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_tree_hl })
apply_tree_hl()
