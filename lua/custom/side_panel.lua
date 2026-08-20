-- One right-hand panel shared by the markdown table of contents and the hover view.
-- The split is owned here; the modules only fill a buffer and follow the editor.
-- Which one shows tracks the edited buffer: markdown gets the outline, any other
-- file the hover, so the two swap in place instead of stacking up.
--   <leader>O  toggle the panel.

local M = {}

local PANEL_WIDTH = 40
local PROVIDERS = { toc = 'custom.markdown_toc', hover = 'custom.hover_panel' }

local win   -- the shared split, nil when the panel is closed
local shown -- provider key currently in the split

local function provider(key) return require(PROVIDERS[key]) end

local function is_open() return win ~= nil and vim.api.nvim_win_is_valid(win) end

-- Provider the current window asks for, or nil when it is only borrowing focus
-- (tree, terminal, float) and whatever is shown should stay.
local function wanted()
  local cur = vim.api.nvim_get_current_win()
  if cur == win then return nil end
  local buf = vim.api.nvim_win_get_buf(cur)
  if vim.bo[buf].buftype ~= '' then return nil end
  return vim.bo[buf].filetype == 'markdown' and 'toc' or 'hover'
end

local function swap(key)
  if shown == key then return end
  if shown then provider(shown).panel_hide() end
  shown = key
  vim.api.nvim_win_set_buf(win, provider(key).panel_buf())
  provider(key).panel_show(win)
end

-- Show the right provider for where the cursor is, then let it re-read its source.
local function sync()
  if not is_open() or not shown then return end
  local key = wanted()
  if key and key ~= shown then swap(key) else provider(shown).panel_sync() end
end

function M.open()
  if is_open() then
    sync()
    return
  end
  -- Opened from a tree or terminal: fall back to the outline when a markdown window
  -- is around to list, so <leader>O off a file tree still lands on the outline.
  local key = wanted() or (provider('toc').source_win() and 'toc' or 'hover')

  local back = vim.api.nvim_get_current_win()
  vim.cmd('botright vsplit')
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, PANEL_WIDTH)
  vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].signcolumn = false, false, 'no'
  vim.wo[win].winfixwidth = true
  vim.wo[win].list, vim.wo[win].spell = false, false

  shown = nil
  swap(key)
  vim.api.nvim_set_current_win(back) -- the panel is a map, not the place to land
  provider(shown).panel_sync()
end

function M.close()
  if is_open() then vim.api.nvim_win_close(win, true) end
end

function M.toggle()
  if is_open() then M.close() else M.open() end
end

-- Closed by hand (`q`, :q, last-window cleanup): drop both providers' state so the
-- next open starts fresh, and so neither keeps following the cursor.
vim.api.nvim_create_autocmd('WinClosed', {
  callback = function(args)
    if not win or tonumber(args.match) ~= win then return end
    win, shown = nil, nil
    vim.schedule(function()
      for key in pairs(PROVIDERS) do provider(key).panel_close() end
    end)
  end,
})

-- Follow the editor across windows. Deferred: a buffer that is still settling its
-- buftype/filetype has had time to land by the next tick.
vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
  callback = function()
    if is_open() then vim.schedule(sync) end
  end,
})

return M
