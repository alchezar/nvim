-- Hover panel: the `gh` float's content (line diagnostics + LSP hover) as a live
-- right-hand split, refreshed on every cursor move. Shares one slot with the
-- markdown table of contents, see custom/side_panel.lua.
--   <leader>O  toggle; q closes. Nothing to show means an empty panel.

local theme = require('config.theme_colors')
local utils = require('config.utils')

local M = {}
local ns = vim.api.nvim_create_namespace('hover_panel')

local DEBOUNCE_MS = 100

-- The `---` separators come back as a full-width run of box glyphs; without an
-- explicit color they take Normal's, which the theme leaves unset (so: white).
-- Match the hover float's border instead.
local function apply_hl()
  vim.api.nvim_set_hl(0, 'HoverPanelDivider', { fg = theme.dark --[[@as string]] })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })
apply_hl()

local buf     -- scratch buffer, alive while the panel slot is open
local win     -- the shared split, nil while hidden
local src_win -- window the hover is read from
local seq = 0 -- request generation; a late reply for an older cursor is dropped
local timer

local function visible()
  return win and vim.api.nvim_win_is_valid(win) and buf and vim.api.nvim_buf_is_valid(buf)
end

-- A concealed URL still occupies its cells when the line wraps, so a long doc link
-- leaves blank rows mid-sentence in a 40-column panel. Drop the target and keep
-- `[label]`, which treesitter still reads as a link, so it stays colored.
local function strip_link_targets(lines)
  local out, fence = {}, false
  for _, line in ipairs(lines) do
    if line:match('^%s*```') then fence = not fence end
    out[#out + 1] = fence and line or (line:gsub('%[([^%]]-)%]%([^)]*%)', '[%1]'))
  end
  return out
end

-- Trim the blank margins and collapse repeated blank lines, the way the hover float
-- does. Private API, so fall back to the raw lines if it ever goes away.
local function normalize(lines, width)
  local ok, out = pcall(vim.lsp.util._normalize_markdown, lines, { width = width })
  return ok and out or lines
end

local function draw(lines)
  if not visible() then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  utils.gray_prose(buf, ns) -- same comment gray the `gh` float uses
  for i, line in ipairs(lines) do
    -- A quantifier binds to the last byte of a multibyte glyph, so no `^─+$` here.
    if line ~= '' and (line:gsub('\u{2500}', '')) == '' then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0,
        { end_col = #line, hl_group = 'HoverPanelDivider' })
    end
  end
  -- New content, new document: show it from the top rather than wherever the
  -- previous hover was scrolled to.
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

-- Window the hover is read from: the current one when it holds a real file. A
-- tree/terminal/float only borrows focus, so it keeps the last source.
local function pick_src()
  local cur = vim.api.nvim_get_current_win()
  if cur == win then return nil end
  if vim.bo[vim.api.nvim_win_get_buf(cur)].buftype ~= '' then return nil end
  return cur
end

local function request()
  if not visible() then return end
  local target = pick_src()
  if not target then return end -- borrowed focus: leave the last hover standing
  src_win = target
  seq = seq + 1
  local mine = seq
  local src_buf = vim.api.nvim_win_get_buf(target)
  utils.hover_lines(target, function(lines)
    if not visible() or mine ~= seq then return end
    -- Nothing under the cursor (a blank line between functions, say): show what the
    -- file itself is about rather than an empty panel.
    if #lines == 0 then lines = utils.file_header_doc(src_buf) end
    draw(normalize(strip_link_targets(lines), vim.api.nvim_win_get_width(win)))
  end)
end

-- Cursor moves fire per keystroke, so let the position settle before asking the LSP.
local function schedule_request()
  if not visible() then return end
  timer = timer or vim.uv.new_timer()
  if not timer then return end
  timer:stop()
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(request))
end

-- side_panel provider interface ------------------------------------------------

function M.panel_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then return buf end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'HoverPanel'
  vim.bo[buf].modifiable = false
  -- Markdown highlighting without the filetype: 'markdown' would make this panel
  -- look like an outline source to the table of contents.
  pcall(vim.treesitter.start, buf, 'markdown')
  vim.keymap.set('n', 'q', function() require('custom.side_panel').close() end,
    { buffer = buf, nowait = true })
  return buf
end

function M.panel_show(w)
  win = w
  vim.wo[win].cursorline = false
  vim.api.nvim_win_set_var(win, 'ft_no_cursorline', true)
  vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].breakindent = true, true, true
  vim.wo[win].conceallevel, vim.wo[win].concealcursor = 2, ''
  request()
end

function M.panel_sync() schedule_request() end

function M.panel_hide()
  win, src_win = nil, nil
  if timer then timer:stop() end
end

function M.panel_close()
  M.panel_hide()
  if buf and vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  buf = nil
end

vim.api.nvim_create_autocmd('CursorMoved', { callback = schedule_request })

-- A diagnostic that lands after the cursor stopped still belongs on screen.
vim.api.nvim_create_autocmd('DiagnosticChanged', {
  callback = function(args)
    if visible() and src_win and vim.api.nvim_win_is_valid(src_win)
        and vim.api.nvim_win_get_buf(src_win) == args.buf then
      schedule_request()
    end
  end,
})

return M
