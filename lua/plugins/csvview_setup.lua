-- csvview: align CSV/TSV columns into a table; delimiter/comment hues from the theme.

local theme = require('config.theme_colors')

local function apply_csv_hl()
  -- Border glyphs and delimiters stay dim so the data, not the grid, leads.
  vim.api.nvim_set_hl(0, 'CsvViewDelimiter', { fg = theme.dark })
  vim.api.nvim_set_hl(0, 'CsvViewComment', { fg = theme.silver, italic = true })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_csv_hl })
apply_csv_hl()

require('csvview').setup({
  view = {
    -- Draw real │ separators instead of just tinting commas (closest to a markdown table).
    display_mode = 'border',
  },
  parser = { comments = { '#', '//' } },
})

-- Auto-render on open.
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'csv', 'tsv' },
  callback = function() vim.cmd('CsvViewEnable') end,
})

-- Raw cursor line, markview hybrid-mode style. csvview aligns via inline virt_text and
-- draws │ via conceal extmarks; neither is reverted by Vim's concealcursor. We drop
-- only the layout (padding + │) on the cursor line so its raw text shows, while the
-- per-column field highlights still run and keep the columns colored like other rows.
local views = require('csvview.view')
local View = views.View
local NS = vim.api.nvim_create_namespace('csv_extmark') -- same namespace csvview registers

-- 1-indexed cursor line, but only when the buffer sits in the current window.
local function cursor_lnum(bufnr)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then return nil end
  return vim.api.nvim_win_get_cursor(win)[1]
end

-- Suppress a layout method on the cursor line; highlight methods are left alone.
local function skip_on_cursor(name)
  local orig = View[name]
  View[name] = function(self, lnum, ...)
    if cursor_lnum(self.bufnr) == lnum then return end
    return orig(self, lnum, ...)
  end
end
skip_on_cursor('_pad_before_field')
skip_on_cursor('_pad_after_field')
skip_on_cursor('_render_delimiter')

-- Clear a line's extmarks and repaint it; render honors the cursor via the wraps above.
local function repaint(view, lnum)
  local ids = view._extmarks[lnum]
  if ids then
    for _, id in ipairs(ids) do pcall(vim.api.nvim_buf_del_extmark, view.bufnr, NS, id) end
    view._extmarks[lnum] = nil
  end
  view:render_lines(lnum, lnum)
end

vim.api.nvim_create_autocmd('User', {
  pattern = 'CsvViewAttach',
  callback = function(args)
    local bufnr = args.data
    local last
    local function refresh()
      local view = views.get(bufnr)
      if not view then return true end -- detached: tear this autocmd down
      local lnum = cursor_lnum(bufnr)
      if lnum and lnum ~= last then
        local prev = last
        last = lnum
        repaint(view, lnum)                  -- raw text, columns still colored
        if prev then repaint(view, prev) end -- previous line back to full layout
      end
    end
    refresh() -- strip layout from the line the cursor lands on at open
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, { buffer = bufnr, callback = refresh })
  end,
})
