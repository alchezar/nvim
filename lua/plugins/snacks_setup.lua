-- Only the picker is enabled, for the GitHub gh_pr / gh_issue / gh_diff sources;
-- it pairs with custom/pr_review.lua, which pushes comments as a pending review
-- that this picker can then display (gh_diff) and submit (gh_submit_review).
require('snacks').setup({
  picker = { enabled = true },
})
