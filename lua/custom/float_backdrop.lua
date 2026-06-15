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
  local dialog = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    -- Trouble (<leader>xx) is a normal split; never dim while it is open.
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'trouble' then return false end
    if qualifies(win) then dialog = true end
  end
  return dialog
end

local group = vim.api.nvim_create_augroup('FloatBackdrop', { clear = true })
local refresh   -- forward-declared; show()'s cursor watcher calls it
local cursor_au -- CursorMoved listener, live only while the backdrop is up

-- Close every backdrop window (matched by marker), not just the tracked one, so
-- a lost reference can never leave a stuck overlay. Also drop the cursor watcher.
local function hide()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].float_backdrop and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  if cursor_au then
    pcall(vim.api.nvim_del_autocmd, cursor_au)
    cursor_au = nil
  end
end

local function show()
  -- Overscan past the edges so Neovide's blur halo falls off-screen.
  local cfg = {
    relative = 'editor',
    row = -1,
    col = -1,
    width = vim.o.columns + 2,
    height = vim.o.lines + 2,
    focusable = false,
    zindex = Z,
    style = 'minimal',
    border = 'none',
  }
  -- Reuse a live backdrop, but resync geometry: the editor may have been resized
  -- or re-laid-out while a dialog stayed open, leaving the old size off-screen.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].float_backdrop and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, cfg)
      return
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  cfg.noautocmd = true
  local win = vim.api.nvim_open_win(buf, false, cfg)
  vim.w[win].float_backdrop = true
  vim.wo[win].winblend = BLEND
  vim.wo[win].winhighlight = 'Normal:FloatBackdrop,NormalFloat:FloatBackdrop'
  vim.bo[buf].bufhidden = 'wipe'
  -- Auto-close floats (gitsigns preview_hunk) close on cursor move from a
  -- non-nested autocmd, so their WinClosed never reaches us. Watch the cursor
  -- only while dimmed, so the backdrop tears down together with them.
  if not cursor_au then
    cursor_au = vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      group = group,
      callback = vim.schedule_wrap(function() refresh() end),
    })
  end
end

refresh = function()
  if any_dialog() then show() else hide() end
end

vim.api.nvim_create_autocmd({ 'WinNew', 'WinClosed', 'WinEnter', 'WinLeave', 'BufEnter', 'VimResized' }, {
  group = group,
  callback = vim.schedule_wrap(refresh),
})
vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = set_hl })

return M
