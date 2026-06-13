-- Dim + blur the editor behind dialog-like floating windows (telescope, the PR
-- review editor, yazi/lazygit, etc.), the way snacks' picker does it. A single
-- full-screen semi-transparent float sits under them; Neovide blurs whatever
-- shows through. Skipped: fidget/notify/hover (not focusable), completion popups
-- (cmp: high zindex), and snacks (it has its own backdrop).

local theme = require('config.theme_colors')

local M = {}
local Z = 30     -- under dialogs (default 50) and fidget (45), over splits
local BLEND = 60 -- 0 opaque .. 100 invisible; matches snacks' default

local function set_hl()
  vim.api.nvim_set_hl(0, 'FloatBackdrop', { bg = theme.black })
end
set_hl()

-- A float we want to dim behind. focusable rules out fidget/notify/hover; the
-- zindex cap drops cmp completion menus (1001); snacks brings its own backdrop.
local function qualifies(win)
  if vim.w[win].float_backdrop then return false end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative == '' or not cfg.focusable then return false end
  if cfg.zindex and cfg.zindex > 100 then return false end
  local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
  return not (ft:match('^snacks') or ft:match('^cmp'))
end

local function any_dialog()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if qualifies(win) then return true end
  end
  return false
end

-- Close every backdrop window (matched by marker), not just the tracked one, so
-- a lost reference can never leave a stuck overlay.
local function hide()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].float_backdrop and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

local function show()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].float_backdrop and vim.api.nvim_win_is_valid(win) then return end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  -- Overscan past the edges so Neovide's blur halo falls off-screen.
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor', row = -1, col = -1,
    width = vim.o.columns + 2, height = vim.o.lines + 2,
    focusable = false, zindex = Z, style = 'minimal', noautocmd = true, border = 'none',
  })
  vim.w[win].float_backdrop = true
  vim.wo[win].winblend = BLEND
  vim.wo[win].winhighlight = 'Normal:FloatBackdrop,NormalFloat:FloatBackdrop'
  vim.bo[buf].bufhidden = 'wipe'
end

local function refresh()
  if any_dialog() then show() else hide() end
end

local group = vim.api.nvim_create_augroup('FloatBackdrop', { clear = true })
vim.api.nvim_create_autocmd({ 'WinNew', 'WinClosed', 'WinEnter', 'WinLeave', 'BufEnter', 'VimResized' }, {
  group = group,
  callback = vim.schedule_wrap(refresh),
})
vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_hl })

return M
