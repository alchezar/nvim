-- Horizontal "minimap" statusline. Layout:
--   <file path> [+]   <bar fills middle>   <E> <W>  L:C  P%
-- The bar maps every file line to a column on the bottom row. Each cell is
-- a composition of a top half (file overview) and a bottom half (markers):
--
-- Top-half (z-ordered, highest wins):
--   cursor   white  ▀ (or full block when no bottom marker)
--   search   pink   ▀ - line currently matches the active /search pattern
--   mark     yellow ▀ - vim letter mark or marks.nvim bookmark (m0..m9)
--   viewport silver ▀ - line is visible on screen right now
--
-- Bottom-half (z-ordered, highest wins):
--   error    red    ▄
--   warn     orange ▄
--   git chg  blue   ▄
--   git add  green  ▄
--   info     cyan   ▄
--   hint     purple ▄
--
-- Cells are rendered with `▀` (fg=top color, bg=bottom color) when both halves
-- carry info, `▄` (fg=bottom color) when only bottom, `▀` (fg=top color) when
-- only top, `█` for cursor alone, and `·` for entirely empty cells.

local M = {}

local theme = require('theme_colors')

-- Color tables drive both highlight setup and per-cell name lookup.
local TOP_COLORS = {
  cursor   = theme.white,
  search   = theme.pink,
  mark     = theme.yellow,
  viewport = theme.silver,
}
-- Ordered by priority (lower index wins on overlap)
local TOP_PRIORITY = { 'cursor', 'search', 'mark', 'viewport' }

local BOT_NAMES = {
  'error', 'warn', 'git_change', 'git_add', 'info', 'hint',
}
local BOT_COLORS = {
  error      = theme.red,
  warn       = theme.orange,
  git_change = theme.blue,
  git_add    = theme.green,
  info       = theme.cyan,
  hint       = theme.purple,
}

local function setup_hl()
  -- Top-only cells: `▀` fg=top_color, no bg
  for name, color in pairs(TOP_COLORS) do
    vim.api.nvim_set_hl(0, 'FpbT_' .. name,
      { fg = color, bold = (name == 'cursor') })
  end
  -- Bottom-only cells: `▄` fg=bottom_color, no bg
  for name, color in pairs(BOT_COLORS) do
    vim.api.nvim_set_hl(0, 'FpbB_' .. name, { fg = color })
  end
  -- Both halves: `▀` fg=top_color, bg=bottom_color
  for tname, tcolor in pairs(TOP_COLORS) do
    for bname, bcolor in pairs(BOT_COLORS) do
      vim.api.nvim_set_hl(0, 'FpbT_' .. tname .. '_B_' .. bname,
        { fg = tcolor, bg = bcolor, bold = (tname == 'cursor') })
    end
  end
  vim.api.nvim_set_hl(0, 'FpbBase',        { fg = theme.dark })
  vim.api.nvim_set_hl(0, 'FpbCursorBlock', { fg = theme.white, bold = true })
  vim.api.nvim_set_hl(0, 'FpbInfoTxt',     { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'FpbFile',        { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'FpbDim',         { fg = theme.dark })
  vim.api.nvim_set_hl(0, 'FpbErrorTxt',    { fg = theme.red })
  vim.api.nvim_set_hl(0, 'FpbWarnTxt',     { fg = theme.orange })
end
setup_hl()

-- Diagnostic severity (1..4) -> bottom-layer name
local DIAG_BOT = { 'error', 'warn', 'info', 'hint' }

local function diag_counts(diags)
  local c = { 0, 0, 0, 0 }
  for _, d in ipairs(diags) do c[d.severity] = c[d.severity] + 1 end
  return c
end

-- lnum -> bottom-name for git-changed lines.
local function git_marks(bufnr)
  local ok, gitsigns = pcall(require, 'gitsigns')
  if not ok then return {} end
  local hunks = gitsigns.get_hunks and gitsigns.get_hunks(bufnr) or {}
  local marks = {}
  for _, h in ipairs(hunks) do
    if h.added and h.added.count and h.added.count > 0 then
      local name = (h.type == 'change') and 'git_change' or 'git_add'
      for lnum = h.added.start, h.added.start + h.added.count - 1 do
        marks[lnum] = name
      end
    end
  end
  return marks
end

-- Set of line numbers that contain a vim letter mark or a marks.nvim bookmark.
local function mark_lines(bufnr)
  local out = {}
  -- vim native a-z marks live in getmarklist
  for _, m in ipairs(vim.fn.getmarklist(bufnr)) do
    local mark_name = m.mark or ''
    -- m.mark is like "'a"; we only want letter marks, skip numeric jump marks
    if mark_name:match("^'[a-zA-Z]$") then
      local lnum = m.pos and m.pos[2]
      if lnum and lnum > 0 then out[lnum] = true end
    end
  end
  -- marks.nvim numbered bookmarks (m0..m9)
  local ok, marks_api = pcall(require, 'marks')
  if ok and marks_api.bookmark_state and marks_api.bookmark_state.groups then
    for _, group in pairs(marks_api.bookmark_state.groups) do
      local buf_marks = group.marks and group.marks[bufnr] or nil
      if buf_marks then
        for lnum, _ in pairs(buf_marks) do
          out[lnum] = true
        end
      end
    end
  end
  return out
end

-- Search-match line set, cached on (bufnr, tick, pattern) to avoid scanning
-- the buffer on every statusline redraw.
local search_cache = { bufnr = -1, tick = -1, pat = '', lines = {} }
local function search_lines(bufnr)
  if vim.v.hlsearch == 0 then return {} end
  local pat = vim.fn.getreg('/')
  if pat == '' then return {} end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if search_cache.bufnr == bufnr
     and search_cache.tick == tick
     and search_cache.pat == pat then
    return search_cache.lines
  end
  local hits = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if vim.fn.match(line, pat) >= 0 then hits[i] = true end
  end
  search_cache = { bufnr = bufnr, tick = tick, pat = pat, lines = hits }
  return hits
end

local function colored_count(n, sev_hl, width)
  local hl = n > 0 and sev_hl or 'FpbDim'
  return string.format('%%#%s#%' .. width .. 'd', hl, n)
end

function M.render()
  local bufnr = vim.api.nvim_win_get_buf(0)
  local total_lines = math.max(1, vim.api.nvim_buf_line_count(bufnr))
  local cursor_lnum = vim.fn.line('.')
  local cursor_col  = vim.fn.col('.')
  local pct = math.floor((cursor_lnum / total_lines) * 100 + 0.5)

  local view_top = vim.fn.line('w0')
  local view_bot = vim.fn.line('w$')

  local diags = vim.diagnostic.get(bufnr)
  local cnt = diag_counts(diags)
  local git = git_marks(bufnr)
  local marks_by_line = mark_lines(bufnr)
  local search_by_line = search_lines(bufnr)

  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':~:.')
  if file == '' then file = '[No Name]' end
  local modified = vim.bo.modified and ' [+]' or ''
  local left_plain = ' ' .. file .. modified .. '  '
  local left_segment = string.format('%%#FpbFile# %s%s  ', file, modified)

  local cnt_w  = 3
  local line_w = math.max(3, #tostring(total_lines))
  local col_w  = 3
  local pct_w  = 3
  local right_plain = string.format(
    '  %' .. cnt_w .. 'd %' .. cnt_w .. 'd  %' .. line_w .. 'd:%' .. col_w .. 'd  %' .. pct_w .. 'd%% ',
    cnt[1], cnt[2], cursor_lnum, cursor_col, pct)
  local right_segment = string.format(
    '  %s %s  %%#FpbInfoTxt#%' .. line_w .. 'd:%-' .. col_w .. 'd  %' .. pct_w .. 'd%%%% ',
    colored_count(cnt[1], 'FpbErrorTxt', cnt_w),
    colored_count(cnt[2], 'FpbWarnTxt',  cnt_w),
    cursor_lnum, cursor_col, pct)

  local bar_width = vim.o.columns - #left_plain - #right_plain
  if bar_width < 6 then
    return left_segment .. '%=' .. right_segment
  end

  local function lnum_to_col(lnum)
    local col = math.floor(((lnum - 1) / math.max(1, total_lines - 1)) * (bar_width - 1)) + 1
    if col < 1 then return 1 end
    if col > bar_width then return bar_width end
    return col
  end

  local view_start = lnum_to_col(view_top)
  local view_end   = lnum_to_col(view_bot)
  local cursor_x   = lnum_to_col(cursor_lnum)

  -- Per-column resolved layers
  local bot = {}    -- col -> bot name
  local function put_bot(col, name, prio)
    -- Resolve by priority: lower prio number wins
    local cur = bot[col]
    if not cur or cur.prio > prio then
      bot[col] = { name = name, prio = prio }
    end
  end
  for _, d in ipairs(diags) do
    local name = DIAG_BOT[d.severity]
    if name then
      -- error=1, warn=2, info=5, hint=6 (git change/add slip between)
      local prio = ({ 1, 2, 5, 6 })[d.severity]
      put_bot(lnum_to_col(d.lnum + 1), name, prio)
    end
  end
  for lnum, name in pairs(git) do
    local prio = (name == 'git_change') and 3 or 4
    put_bot(lnum_to_col(lnum), name, prio)
  end

  local search_col = {}
  for lnum in pairs(search_by_line) do
    search_col[lnum_to_col(lnum)] = true
  end
  local mark_col = {}
  for lnum in pairs(marks_by_line) do
    mark_col[lnum_to_col(lnum)] = true
  end

  local parts = {}
  for col = 1, bar_width do
    -- Resolve top layer
    local top
    if col == cursor_x then
      top = 'cursor'
    elseif search_col[col] then
      top = 'search'
    elseif mark_col[col] then
      top = 'mark'
    elseif col >= view_start and col <= view_end then
      top = 'viewport'
    end

    local b = bot[col] and bot[col].name or nil

    local hl, ch
    if top == 'cursor' and not b then
      hl, ch = 'FpbCursorBlock', '█'
    elseif top and b then
      hl, ch = 'FpbT_' .. top .. '_B_' .. b, '▀'
    elseif top then
      hl, ch = 'FpbT_' .. top, '▀'
    elseif b then
      hl, ch = 'FpbB_' .. b, '▄'
    else
      hl, ch = 'FpbBase', '·'
    end
    parts[#parts+1] = '%#' .. hl .. '#' .. ch
  end
  return left_segment .. table.concat(parts) .. right_segment
end

local group = vim.api.nvim_create_augroup('FilePositionBar', { clear = true })
vim.api.nvim_create_autocmd(
  { 'CursorMoved', 'CursorMovedI', 'WinScrolled', 'BufEnter',
    'DiagnosticChanged', 'VimResized', 'TextChanged', 'TextChangedI' },
  { group = group, callback = function() vim.cmd('redrawstatus') end }
)
vim.api.nvim_create_autocmd('User', {
  group = group, pattern = 'GitSignsUpdate',
  callback = function() vim.cmd('redrawstatus') end,
})
-- Search pattern changes redraw via CmdlineLeave on /, ?, and after :nohlsearch
vim.api.nvim_create_autocmd({ 'CmdlineLeave' }, {
  group = group, callback = function() vim.cmd('redrawstatus') end,
})
vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = setup_hl })

vim.opt.statusline = '%!v:lua.require("file_position_bar").render()'
vim.opt.laststatus = 3

return M
