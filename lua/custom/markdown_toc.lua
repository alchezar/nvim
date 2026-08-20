-- Table of contents panel for markdown: the right-hand panel listing the ATX
-- headings of the edited buffer, cursorline parked on the current section. Shares
-- one slot with the hover view, see custom/side_panel.lua.
--   :MarkdownToc / <leader>O  toggle; <CR> jumps + focuses, o jumps and stays,
--   <Tab>/za fold, zM/zR fold all, q closes.

local theme = require('config.theme_colors')

local M = {}
local ns = vim.api.nvim_create_namespace('markdown_toc')

local ARROW_CLOSED, ARROW_OPEN = '\u{F460}', '\u{F47C}' -- same expanders as the file tree
local NO_SOURCE = 'Table of contents: no markdown buffer'

-- H1..H6 in the colors markview paints them (plugins/markdown.lua).
local HEADING_COLORS = { 'red', 'orange', 'yellow', 'green', 'blue', 'purple' }

local function apply_hl()
  for level, color in ipairs(HEADING_COLORS) do
    vim.api.nvim_set_hl(0, 'MarkdownTocH' .. level,
      { fg = theme[color] --[[@as string]], bold = level <= 2 })
  end
  vim.api.nvim_set_hl(0, 'MarkdownTocArrow', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'MarkdownTocEmpty', { fg = theme.dark })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })
apply_hl()

local collapsed = {} -- heading key -> true (folded); reset on open, kept while the panel lives
local state          -- panel buffer + source; lives as long as the buffer, nil when closed

-- Window to outline: the current one when it holds markdown. A tree/terminal/float
-- (buftype ~= '') is only borrowed focus, so look past it; a real file of another
-- type is not a document to list.
function M.source_win()
  local cur = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(cur)
  if vim.bo[buf].filetype == 'markdown' then return cur end
  if vim.bo[buf].buftype == '' then return nil end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == '' and vim.bo[b].filetype == 'markdown' then return w end
  end
end

local function valid(st)
  return st and st.win and vim.api.nvim_win_is_valid(st.win)
end

local function src_valid(st)
  return st.src_win and vim.api.nvim_win_is_valid(st.src_win)
      and vim.api.nvim_win_get_buf(st.src_win) == st.src_buf
end

-- Headings with a fold key and a children flag. The key is the ancestor text
-- path, so folds survive edits that shift line numbers.
local function outline(bufnr)
  local items = require('custom.markdown_outline').headings(bufnr)
  local path, seen = {}, {}
  for i, h in ipairs(items) do
    local parent = h.indent > 0 and path[h.indent] or nil
    local base = (parent or '') .. '/' .. h.text
    local n = (seen[base] or 0) + 1
    seen[base] = n -- same title twice under one parent: keep the keys apart
    h.key = n > 1 and (base .. '#' .. n) or base
    h.parent = parent
    h.has_children = items[i + 1] ~= nil and items[i + 1].indent > h.indent
    path[h.indent + 1] = h.key
  end
  return items
end

-- Single greyed line for a panel with nothing to list.
local function note_lines(note)
  return { '  ' .. note }, { { line = 0, col = 2, len = #note, hl = 'MarkdownTocEmpty' } }
end

-- Headings -> buffer lines + per-line meta. A folded heading hides its nested ones.
local function render(items)
  local lines, hls, meta, row_of_key = {}, {}, {}, {}
  local hide_below
  for _, h in ipairs(items) do
    if not (hide_below and h.indent > hide_below) then
      hide_below = nil
      local ind = 2 * h.indent
      local arrow = h.has_children and (collapsed[h.key] and ARROW_CLOSED or ARROW_OPEN) or ' '
      lines[#lines + 1] = ('%s%s %s'):format((' '):rep(ind), arrow, h.text)
      local row = #lines
      hls[#hls + 1] = { line = row - 1, col = ind, len = #arrow, hl = 'MarkdownTocArrow' }
      hls[#hls + 1] = {
        line = row - 1,
        col = ind + #arrow + 1,
        len = #h.text,
        hl = 'MarkdownTocH' .. h.level,
      }
      meta[row] = h
      row_of_key[h.key] = row
      if h.has_children and collapsed[h.key] then hide_below = h.indent end
    end
  end
  if #lines == 0 then lines, hls = note_lines('(no headings)') end
  return lines, hls, meta, row_of_key
end

-- Re-read the source buffer and redraw in place; the panel cursor keeps its row.
local function repaint(st)
  if not valid(st) then return end
  local lines, hls, meta, row_of_key
  if st.src_buf and vim.api.nvim_buf_is_valid(st.src_buf) then
    st.items = outline(st.src_buf)
    st.by_key = {}
    for _, h in ipairs(st.items) do st.by_key[h.key] = h end
    st.tick = vim.b[st.src_buf].changedtick
    lines, hls, meta, row_of_key = render(st.items)
  else -- detached: keep the panel, say why it is empty
    st.items, st.by_key, meta, row_of_key = {}, {}, {}, {}
    lines, hls = note_lines(NO_SOURCE)
  end
  st.meta, st.row_of_key = meta, row_of_key
  vim.bo[st.buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
  vim.bo[st.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(st.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(st.buf, ns, h.line, h.col, {
      end_col = h.col + h.len,
      hl_group = h.hl,
    })
  end
  -- Folding shrinks the list under a cursor that sat on a now-hidden row.
  local row = vim.api.nvim_win_get_cursor(st.win)[1]
  if row > #lines then vim.api.nvim_win_set_cursor(st.win, { #lines, 0 }) end
end

-- Section owning `lnum`: the last heading at or above it.
local function section_at(items, lnum)
  local found
  for _, h in ipairs(items) do
    if h.lnum > lnum then break end
    found = h
  end
  return found
end

-- Park the panel cursor on the current section, without stealing focus. A section
-- hidden inside a fold highlights its nearest visible ancestor instead.
local function follow(st)
  if not valid(st) or not src_valid(st) then return end
  if vim.api.nvim_get_current_win() == st.win then return end -- user is browsing the panel
  local h = section_at(st.items, vim.api.nvim_win_get_cursor(st.src_win)[1])
  while h and not st.row_of_key[h.key] do h = h.parent and st.by_key[h.parent] or nil end
  -- Above the first heading: nothing to point at, so drop the stale highlight.
  vim.api.nvim_win_set_var(st.win, 'ft_no_cursorline', h == nil)
  vim.wo[st.win].cursorline = h ~= nil
  if not h then return end
  -- No centering: nvim scrolls the panel only when the row falls off it, so reading
  -- down a document doesn't drag the whole outline along.
  vim.api.nvim_win_set_cursor(st.win, { st.row_of_key[h.key], 0 })
end

-- Move the edited window onto the heading under the panel cursor.
local function jump(st, focus)
  if not valid(st) or not src_valid(st) then return end
  local h = st.meta[vim.api.nvim_win_get_cursor(st.win)[1]]
  if not h then return end
  vim.api.nvim_win_set_cursor(st.src_win, { h.lnum, 0 })
  vim.api.nvim_win_call(st.src_win, function() vim.cmd('normal! zz') end)
  if focus then vim.api.nvim_set_current_win(st.src_win) end
end

local function toggle_fold(st)
  if not valid(st) then return end
  local h = st.meta[vim.api.nvim_win_get_cursor(st.win)[1]]
  if not h or not h.has_children then return end
  collapsed[h.key] = not collapsed[h.key] or nil
  repaint(st)
end

local function set_all_folds(st, folded)
  if not valid(st) then return end
  for _, h in ipairs(st.items) do
    if h.has_children then collapsed[h.key] = folded or nil end
  end
  repaint(st)
end

-- No markdown to outline: empty the panel instead of closing it, so hopping through
-- other files doesn't cost a reopen. It refills as soon as markdown is focused again.
local function detach(st)
  if not valid(st) then return end
  st.src_win, st.src_buf = nil, nil
  vim.api.nvim_win_set_var(st.win, 'ft_no_cursorline', true)
  vim.wo[st.win].cursorline = false
  repaint(st)
end

-- Re-aim the panel at another markdown buffer (window switch, or the source closed).
local function retarget(st, win)
  st.src_win, st.src_buf = win, vim.api.nvim_win_get_buf(win)
  repaint(st)
  follow(st)
end

-- side_panel provider interface ------------------------------------------------

function M.panel_buf()
  if state and vim.api.nvim_buf_is_valid(state.buf) then return state.buf end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].filetype = 'MarkdownToc'
  state = { buf = buf }
  collapsed = {} -- fresh panel: show the whole outline

  local kmap = function(lhs, fn) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true }) end
  kmap('<CR>', function() jump(state, true) end)
  kmap('o', function() jump(state, false) end)
  kmap('<2-LeftMouse>', function() jump(state, true) end)
  -- Single click jumps, like the file tree. On release, so the unmapped <LeftMouse>
  -- has already moved the cursor onto the clicked row.
  kmap('<LeftRelease>', function()
    if require('config.utils').clicked_line() then jump(state, true) end
  end)
  kmap('<Tab>', function() toggle_fold(state) end)
  kmap('za', function() toggle_fold(state) end)
  kmap('zM', function() set_all_folds(state, true) end)
  kmap('zR', function() set_all_folds(state, false) end)
  kmap('q', function() require('custom.side_panel').close() end)
  return buf
end

function M.panel_show(win)
  state.win = win
  -- The hover view leaves the window wrapped and concealing; an outline is neither.
  vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].breakindent = false, false, false
  vim.wo[win].conceallevel = 0
  vim.wo[win].cursorline = true
  local src = M.source_win()
  if src then retarget(state, src) else detach(state) end
end

-- Window or buffer switched: take over another markdown buffer, or empty out.
function M.panel_sync()
  if not valid(state) then return end
  local win = vim.api.nvim_get_current_win()
  if win == state.win then return end          -- user is browsing the panel
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= '' then return end -- tree/terminal/float only borrows focus
  if vim.bo[buf].filetype ~= 'markdown' then
    detach(state)
  elseif win ~= state.src_win or buf ~= state.src_buf then
    retarget(state, win)
  else
    follow(state)
  end
end

function M.panel_hide()
  if state then state.win = nil end
end

function M.panel_close()
  if not state then return end
  local buf = state.buf
  state = nil
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
end

-- Toggle the table of contents in the shared right-hand panel.
function M.toggle() require('custom.side_panel').toggle() end

vim.api.nvim_create_autocmd('CursorMoved', {
  callback = function()
    if valid(state) then follow(state) end
  end,
})

-- Headings edited: redraw, debounced so typing doesn't re-parse per keystroke.
local refresh_timer
vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
  callback = function(args)
    if not valid(state) or args.buf ~= state.src_buf then return end
    refresh_timer = refresh_timer or vim.uv.new_timer()
    if not refresh_timer then return end
    refresh_timer:stop()
    refresh_timer:start(150, 0, vim.schedule_wrap(function()
      if not valid(state) or vim.b[state.src_buf].changedtick == state.tick then return end
      repaint(state)
      follow(state)
    end))
  end,
})

-- The edited window was closed: hand the panel to another markdown window, or empty it.
vim.api.nvim_create_autocmd('WinClosed', {
  callback = function(args)
    if not valid(state) or tonumber(args.match) ~= state.src_win then return end
    vim.schedule(function()
      if not valid(state) then return end
      local win = M.source_win()
      if win and win ~= state.win then retarget(state, win) else detach(state) end
    end)
  end,
})

vim.api.nvim_create_user_command('MarkdownToc', M.toggle, { desc = 'Markdown: toggle table of contents panel' })

return M
