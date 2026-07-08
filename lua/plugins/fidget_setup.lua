-- Terminal-only now (Neovide uses the top progress bar), so no custom window bg:
-- the lighter FidgetNormal was there to fight Neovide's non-transparent floats.
require('fidget').setup({
  -- String (not table) icon = no spinner animation.
  progress = { display = { progress_icon = '' } },
  notification = { window = { border = 'rounded' } },
})
