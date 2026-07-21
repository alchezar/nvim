-- Word-wrapped markdown tables under 'wrap': long cells break inside the column
-- instead of dragging the row off-screen. Source rows hidden with conceal_lines,
-- the box drawn as one virt_lines block (technique after markdown-table-wrap.nvim).

local theme = require('config.theme_colors')
local ns = vim.api.nvim_create_namespace('kinder_md_table_wrap')

local M = {}

local MIN_COL = 3
local B = { -- rounded box-drawing pieces
  h = '─', v = '│',
  tl = '╭', tj = '┬', tr = '╮',
  ml = '├', mj = '┼', mr = '┤',
  bl = '╰', bj = '┴', br = '╯',
}

local function apply_hl()
  vim.api.nvim_set_hl(0, 'KinderTableBorder', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'KinderTableText', { fg = theme.fg })
  vim.api.nvim_set_hl(0, 'KinderTableBold', { fg = theme.teal, bold = true })
  vim.api.nvim_set_hl(0, 'KinderTableItalic', { fg = theme.fg, italic = true })
  vim.api.nvim_set_hl(0, 'KinderTableCode', { fg = theme.emerald })
  vim.api.nvim_set_hl(0, 'KinderTableLink', { fg = theme.blue })
end
apply_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })

local function strwidth(s) return vim.api.nvim_strwidth(s) end

-- Split cell text into styled segments, dropping the markup punctuation itself:
-- `code`, **bold**, *italic*, [label](url). Order matters - test ** before *.
local function parse_inline(text)
  local segs, plain, i = {}, {}, 1
  local function flush()
    if #plain > 0 then segs[#segs + 1] = { text = table.concat(plain), hl = 'KinderTableText' }; plain = {} end
  end
  while i <= #text do
    local rest = text:sub(i)
    local code = rest:match('^`([^`]+)`')
    local bold = rest:match('^%*%*(.-)%*%*')
    local lbl, url = rest:match('^%[([^%]]*)%]%(([^)]*)%)')
    local em = rest:match('^%*([^%*]+)%*')
    if code then
      flush(); segs[#segs + 1] = { text = code, hl = 'KinderTableCode' }; i = i + #code + 2
    elseif bold and #bold > 0 then
      flush(); segs[#segs + 1] = { text = bold, hl = 'KinderTableBold' }; i = i + #bold + 4
    elseif lbl then
      flush(); segs[#segs + 1] = { text = lbl, hl = 'KinderTableLink' }; i = i + #lbl + #url + 4
    elseif em then
      flush(); segs[#segs + 1] = { text = em, hl = 'KinderTableItalic' }; i = i + #em + 2
    else
      plain[#plain + 1] = text:sub(i, i); i = i + 1
    end
  end
  flush()
  return segs
end

-- Parsed segments of every real cell (class == 'column') in a row.
local function cell_segments(row)
  local out = {}
  for _, c in ipairs(row) do
    if c.class == 'column' then out[#out + 1] = parse_inline(vim.trim(c.text)) end
  end
  return out
end

local function segs_width(segs)
  local w = 0
  for _, s in ipairs(segs) do w = w + strwidth(s.text) end
  return w
end

-- Segments -> word tokens carrying their hl, so wrapping keeps the styling.
local function tokenize(segs)
  local toks = {}
  for _, s in ipairs(segs) do
    for word in s.text:gmatch('%S+') do toks[#toks + 1] = { text = word, hl = s.hl } end
  end
  return toks
end

-- Greedy word wrap to a display-width limit; each screen line is a token list.
-- A token wider than the limit is split by character, keeping its hl.
local function wrap_tokens(toks, limit)
  if limit < 1 then limit = 1 end
  local lines, cur, curw = {}, {}, 0
  local function flush() lines[#lines + 1] = cur; cur, curw = {}, 0 end
  for _, t in ipairs(toks) do
    local tw = strwidth(t.text)
    if tw > limit then
      if curw > 0 then flush() end
      local piece = ''
      for ch in t.text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if strwidth(piece .. ch) > limit then lines[#lines + 1] = { { text = piece, hl = t.hl } }; piece = ch
        else piece = piece .. ch end
      end
      if piece ~= '' then cur = { { text = piece, hl = t.hl } }; curw = strwidth(piece) end
    else
      local add = curw == 0 and tw or (curw + 1 + tw)
      if curw > 0 and add > limit then flush(); add = tw end
      cur[#cur + 1] = t; curw = add
    end
  end
  if #cur > 0 or #lines == 0 then flush() end
  return lines
end

-- Share the available text width across columns: start from natural widths,
-- clamp to a minimum, then trim the widest until the row fits.
local function distribute(cols_count, natural, available)
  local border_cost = 1 + cols_count * 3 -- one leading '|' plus ' | ' per column
  local budget = math.max(cols_count * MIN_COL, available - border_cost)
  local widths = {}
  for i = 1, cols_count do widths[i] = math.max(MIN_COL, natural[i]) end
  local function sum() local t = 0; for _, w in ipairs(widths) do t = t + w end; return t end
  while sum() > budget do
    local widest = 1
    for i = 2, cols_count do if widths[i] > widths[widest] then widest = i end end
    if widths[widest] <= MIN_COL then break end
    widths[widest] = widths[widest] - 1
  end
  return widths
end

-- One screen line of one cell -> chunk list " word word …" padded to the column.
local function cell_chunks(tokens, w, align)
  local chunks, used = {}, 0
  for i, t in ipairs(tokens) do
    if i > 1 then chunks[#chunks + 1] = { ' ', 'KinderTableText' }; used = used + 1 end
    chunks[#chunks + 1] = { t.text, t.hl }; used = used + strwidth(t.text)
  end
  local missing = math.max(0, w - used)
  local left, right = 0, missing
  if align == 'right' then left, right = missing, 0
  elseif align == 'center' then left = math.floor(missing / 2); right = missing - left end
  local out = { { ' ' .. (' '):rep(left), 'KinderTableText' } }
  vim.list_extend(out, chunks)
  out[#out + 1] = { (' '):rep(right) .. ' ', 'KinderTableText' }
  return out
end

-- A border row as a single-chunk virt line (list of [text, hl] pairs).
local function border(left, join, right, widths)
  local parts = { left }
  for i, w in ipairs(widths) do
    parts[#parts + 1] = B.h:rep(w + 2)
    parts[#parts + 1] = i == #widths and right or join
  end
  return { { table.concat(parts), 'KinderTableBorder' } }
end

-- One logical row (per-column segment lists) -> its wrapped virt lines.
local function row_lines(cells, widths, aligns)
  local wrapped, height = {}, 1
  for i = 1, #widths do
    wrapped[i] = wrap_tokens(tokenize(cells[i] or {}), widths[i])
    height = math.max(height, #wrapped[i])
  end
  local out = {}
  for line = 1, height do
    local chunks = { { B.v, 'KinderTableBorder' } }
    for i = 1, #widths do
      vim.list_extend(chunks, cell_chunks(wrapped[i][line] or {}, widths[i], aligns[i]))
      chunks[#chunks + 1] = { B.v, 'KinderTableBorder' }
    end
    out[#out + 1] = chunks
  end
  return out
end

-- Build every rendered virt line for the table, top border to bottom border.
local function build(item, available)
  local header = cell_segments(item.header)
  local cols = #header
  if cols == 0 then return nil end

  local data = {}
  for _, r in ipairs(item.rows) do data[#data + 1] = cell_segments(r) end

  local natural = {}
  for i = 1, cols do natural[i] = segs_width(header[i]) end
  for _, row in ipairs(data) do
    for i = 1, cols do natural[i] = math.max(natural[i], segs_width(row[i] or {})) end
  end

  local aligns = {}
  for i = 1, cols do
    local a = (item.alignments or {})[i]
    aligns[i] = (a == 'left' or a == 'center' or a == 'right') and a or 'left'
  end

  local widths = distribute(cols, natural, available)
  local lines = { border(B.tl, B.tj, B.tr, widths) }
  vim.list_extend(lines, row_lines(header, widths, aligns))
  lines[#lines + 1] = border(B.ml, B.mj, B.mr, widths)
  for _, row in ipairs(data) do
    vim.list_extend(lines, row_lines(row, widths, aligns))
  end
  lines[#lines + 1] = border(B.bl, B.bj, B.br, widths)
  return lines
end

-- Clear this module's marks over the table, plus the anchor rows just outside it
-- (the virt_lines block hangs on row_start-1 or row_end, not inside the range).
function M.clear(buffer, item)
  local from = math.max(0, item.range.row_start - 1)
  vim.api.nvim_buf_clear_namespace(buffer, ns, from, item.range.row_end + 1)
end

function M.render(buffer, item, win)
  M.clear(buffer, item)
  local row_start, row_end = item.range.row_start, item.range.row_end

  local textoff = vim.fn.getwininfo(win)[1].textoff
  local available = math.max(20, vim.api.nvim_win_get_width(win) - textoff)
  local lines = build(item, available)
  if not lines then return end

  -- Hide every source row to zero height (conceal_lines needs conceallevel>0,
  -- which sync_raw sets to 2 under wrap), then draw the box as virtual lines.
  for row = row_start, row_end - 1 do
    vim.api.nvim_buf_set_extmark(buffer, ns, row, 0, { conceal_lines = '' })
  end

  -- virt_lines are ignored on a conceal_lines row, so anchor off the table: the row
  -- above (shown below it), else the row below (shown above it) for a top-of-file table.
  if row_start > 0 then
    vim.api.nvim_buf_set_extmark(buffer, ns, row_start - 1, 0, { virt_lines = lines })
  elseif row_end < vim.api.nvim_buf_line_count(buffer) then
    vim.api.nvim_buf_set_extmark(buffer, ns, row_end, 0, { virt_lines = lines, virt_lines_above = true })
  end
end

return M
