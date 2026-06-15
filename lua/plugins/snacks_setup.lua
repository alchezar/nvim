-- Only the picker is enabled, for the GitHub gh_pr / gh_issue / gh_diff sources;
-- it pairs with custom/pr_review.lua, which pushes comments as a pending review
-- that this picker can then display (gh_diff) and submit (gh_submit_review).
require('snacks').setup({
  picker = { enabled = true },
})

-- snacks.gh derives its diff colors from NormalFloat/Normal fg at load time; our
-- theme leaves those fg-less, so pin an fg here or the gh_pr finder fails to load.
local palette = require('config.theme_colors')
local function apply_gh_hl()
  vim.api.nvim_set_hl(0, 'SnacksGhNormalFloat', { fg = palette.fg, bg = palette.float })
end
apply_gh_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_gh_hl })
