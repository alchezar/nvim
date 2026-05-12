-- diffview.nvim: side-by-side diff viewer and 3-way merge conflict resolver.
--
-- Workflow during a merge conflict:
--   :DiffviewOpen          - file panel lists unmerged paths
--   <CR> on a file         - opens 3 windows: OURS | THEIRS on top, working below
--   ]x / [x                - jump to next / previous conflict
--   <leader>co             - choose OURS  (current branch)
--   <leader>ct             - choose THEIRS (incoming)
--   <leader>cb             - choose BASE  (common ancestor)
--   <leader>cO/cT/cB       - choose all OURS/THEIRS/BASE in the file
--   <leader>c0             - delete the conflict region
--   :DiffviewClose         - close (after :w on the working file)

local theme = require('theme_colors')

require('diffview').setup({
  use_icons = true,
  enhanced_diff_hl = true,
  view = {
    default      = { layout = 'diff2_horizontal' },
    -- 3-pane merge: OURS | THEIRS on top, working file below. BASE omitted -
    -- common ancestor rarely adds signal when you already see both sides.
    merge_tool   = {
      layout = 'diff3_mixed',
      disable_diagnostics = true,  -- LSP would flag conflict markers as errors
      winbar_info = true,
    },
    file_history = { layout = 'diff2_horizontal' },
  },
  file_panel = {
    listing_style = 'tree',
    win_config = { position = 'left', width = 35 },
  },
})

-- Diff colors used inside the diff/merge panels. Subtle bg tints so the
-- foreground syntax highlighting still reads clearly.
vim.api.nvim_set_hl(0, 'DiffAdd',    { bg = '#1f3a2a' })
vim.api.nvim_set_hl(0, 'DiffDelete', { bg = '#3a1f1f', fg = theme.silver })
vim.api.nvim_set_hl(0, 'DiffChange', { bg = '#2a2f3a' })
vim.api.nvim_set_hl(0, 'DiffText',   { bg = '#3a3520', fg = theme.orange, bold = true })

-- Diffview file panel (left sidebar listing changed/unmerged files)
vim.api.nvim_set_hl(0, 'DiffviewFilePanelTitle',    { fg = theme.cyan,   bold = true })
vim.api.nvim_set_hl(0, 'DiffviewFilePanelCounter',  { fg = theme.orange })
vim.api.nvim_set_hl(0, 'DiffviewFilePanelFileName', { fg = theme.gray })
vim.api.nvim_set_hl(0, 'DiffviewFilePanelPath',     { fg = theme.silver })
vim.api.nvim_set_hl(0, 'DiffviewStatusUnmerged',    { fg = theme.red,    bold = true })
vim.api.nvim_set_hl(0, 'DiffviewStatusModified',    { fg = theme.yellow })
vim.api.nvim_set_hl(0, 'DiffviewStatusUntracked',   { fg = theme.green })
vim.api.nvim_set_hl(0, 'DiffviewStatusAdded',       { fg = theme.green })
vim.api.nvim_set_hl(0, 'DiffviewStatusDeleted',     { fg = theme.red })
vim.api.nvim_set_hl(0, 'DiffviewStatusRenamed',     { fg = theme.blue })
