-- Table of contents panel for markdown: a split on the right listing the ATX
-- headings of the edited buffer, cursorline parked on the current section.
--   :MarkdownToc / <leader>O  toggle; <CR> jumps + focuses, o jumps and stays,
--   <Tab>/za fold, zM/zR fold all, q closes.

local theme = require('config.theme_colors')

local M = {}
local ns = vim.api.nvim_create_namespace('markdown_toc')

local PANEL_WIDTH = 40
local ARROW_CLOSED, ARROW_OPEN = '\u{F460}', '\u{F47C}' -- same expanders as the file tree

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
local active         -- open panel's state, for the follow/refresh autocmds; nil when closed

-- Tab window showing filetype ft, or nil.
local function win_by_ft(ft)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == ft then return w end
  end
end

-- Window to outline: the current one when it holds markdown. A tree/terminal/float
-- (buftype ~= '') is only borrowed focus, so look past it; a real file of another
-- type is not a document to list.
local function markdown_win()
  local cur = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(cur)
  if vim.bo[buf].filetype == 'markdown' then return cur end
  if vim.bo[buf].buftype == '' then return nil end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'markdown' then return w end
  end
end

local function valid(state)
  return state and state.win and vim.api.nvim_win_is_valid(state.win)
end

local function src_valid(state)
  return state.src_win and vim.api.nvim_win_is_valid(state.src_win)
      and vim.api.nvim_win_get_buf(state.src_win) == state.src_buf
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
  if #lines == 0 then
    local note = '(no headings)'
    lines[1] = '  ' .. note
    hls[1] = { line = 0, col = 2, len = #note, hl = 'MarkdownTocEmpty' }
  end
  return lines, hls, meta, row_of_key
end

-- Re-read the source buffer and redraw in place; the panel cursor keeps its row.
local function repaint(state)
  if not (valid(state) and vim.api.nvim_buf_is_valid(state.src_buf)) then return end
  state.items = outline(state.src_buf)
  state.by_key = {}
  for _, h in ipairs(state.items) do state.by_key[h.key] = h end
  state.tick = vim.b[state.src_buf].changedtick

  local lines, hls, meta, row_of_key = render(state.items)
  state.meta, state.row_of_key = meta, row_of_key
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, h.line, h.col, {
      end_col = h.col + h.len,
      hl_group = h.hl,
    })
  end
  -- Folding shrinks the list under a cursor that sat on a now-hidden row.
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  if row > #lines then vim.api.nvim_win_set_cursor(state.win, { #lines, 0 }) end
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
local function follow(state)
  if not valid(state) or not src_valid(state) then return end
  if vim.api.nvim_get_current_win() == state.win then return end -- user is browsing the panel
  local h = section_at(state.items, vim.api.nvim_win_get_cursor(state.src_win)[1])
  while h and not state.row_of_key[h.key] do h = h.parent and state.by_key[h.parent] or nil end
  -- Above the first heading: nothing to point at, so drop the stale highlight.
  vim.api.nvim_win_set_var(state.win, 'ft_no_cursorline', h == nil)
  vim.wo[state.win].cursorline = h ~= nil
  if not h then return end
  -- No centering: nvim scrolls the panel only when the row falls off it, so reading
  -- down a document doesn't drag the whole outline along.
  vim.api.nvim_win_set_cursor(state.win, { state.row_of_key[h.key], 0 })
end

-- Move the edited window onto the heading under the panel cursor.
local function jump(state, focus)
  local h = state.meta[vim.api.nvim_win_get_cursor(state.win)[1]]
  if not h or not src_valid(state) then return end
  vim.api.nvim_win_set_cursor(state.src_win, { h.lnum, 0 })
  vim.api.nvim_win_call(state.src_win, function() vim.cmd('normal! zz') end)
  if focus then vim.api.nvim_set_current_win(state.src_win) end
end

local function toggle_fold(state)
  local h = state.meta[vim.api.nvim_win_get_cursor(state.win)[1]]
  if not h or not h.has_children then return end
  collapsed[h.key] = not collapsed[h.key] or nil
  repaint(state)
end

local function set_all_folds(state, folded)
  for _, h in ipairs(state.items) do
    if h.has_children then collapsed[h.key] = folded or nil end
  end
  repaint(state)
end

local function close(state)
  if valid(state) then vim.api.nvim_win_close(state.win, true) end
end

-- Re-aim the panel at another markdown buffer (window switch, or the source closed).
local function retarget(state, win)
  state.src_win, state.src_buf = win, vim.api.nvim_win_get_buf(win)
  repaint(state)
  follow(state)
end

-- Toggle the table of contents in a full-height split on the right.
function M.toggle()
  local existing = win_by_ft('MarkdownToc')
  if existing then
    vim.api.nvim_win_close(existing, true)
    return
  end

  local src_win = markdown_win()
  if not src_win then
    vim.notify('Table of contents: no markdown buffer', vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'MarkdownToc'

  local back = vim.api.nvim_get_current_win()
  vim.cmd('botright vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, PANEL_WIDTH)
  vim.wo[win].cursorline = true
  vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].signcolumn = false, false, 'no'
  vim.wo[win].winfixwidth = true
  vim.wo[win].wrap, vim.wo[win].list, vim.wo[win].spell = false, false, false

  local state = { buf = buf, win = win, src_win = src_win, src_buf = vim.api.nvim_win_get_buf(src_win) }
  collapsed = {} -- fresh window: show the whole outline
  repaint(state) -- meta ready before `active` is published to follow
  active = state
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function() if active and active.buf == buf then active = nil end end,
  })

  vim.api.nvim_set_current_win(back) -- the panel is a map, not the place to land
  follow(state)

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
  kmap('q', function() close(state) end)
end

vim.api.nvim_create_autocmd('CursorMoved', {
  callback = function()
    if active then follow(active) end
  end,
})

-- Follow the editor across windows: another markdown buffer takes the panel over, a
-- real file of any other type closes it (its outline would be a stale document).
-- Trees, terminals and floats only borrow focus, so they leave the panel alone.
vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
  callback = function(args)
    local st = active
    if not valid(st) then return end
    local win = vim.api.nvim_get_current_win()
    if win == st.win or vim.api.nvim_win_get_buf(win) ~= args.buf then return end
    if vim.bo[args.buf].buftype ~= '' then return end
    if vim.bo[args.buf].filetype ~= 'markdown' then
      -- On the next tick: closing mid-autocmd can trip window ops, and a buffer that
      -- is still settling its buftype/filetype has had time to land by then.
      vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        if vim.bo[buf].buftype == '' and vim.bo[buf].filetype ~= 'markdown' then close(st) end
      end)
      return
    end
    if win ~= st.src_win or args.buf ~= st.src_buf then retarget(st, win) end
  end,
})

-- Headings edited: redraw, debounced so typing doesn't re-parse per keystroke.
local refresh_timer
vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
  callback = function(args)
    local st = active
    if not valid(st) or args.buf ~= st.src_buf then return end
    refresh_timer = refresh_timer or vim.uv.new_timer()
    if not refresh_timer then return end
    refresh_timer:stop()
    refresh_timer:start(150, 0, vim.schedule_wrap(function()
      local cur = active
      if not valid(cur) or vim.b[cur.src_buf].changedtick == cur.tick then return end
      repaint(cur)
      follow(cur)
    end))
  end,
})

-- The edited window was closed: hand the panel to another markdown window, if any.
vim.api.nvim_create_autocmd('WinClosed', {
  callback = function(args)
    local st = active
    if not valid(st) or tonumber(args.match) ~= st.src_win then return end
    vim.schedule(function()
      if not valid(active) then return end
      local win = markdown_win()
      if win and win ~= active.win then retarget(active, win) end
    end)
  end,
})

vim.api.nvim_create_user_command('MarkdownToc', M.toggle, { desc = 'Markdown: toggle table of contents panel' })

return M
