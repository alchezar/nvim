-- Word-wrapped markdown tables under 'wrap': long cells break inside the column
-- instead of dragging the row off-screen. The box is split into per-row segments
-- anchored on the source rows themselves, so a tall table stays scrollable.
-- Cells are not parsed as markdown: they replay what nvim would draw for their bytes
-- (treesitter highlights and conceals plus markview's inline marks).

local theme = require('config.theme_colors')
local ns = vim.api.nvim_create_namespace('kinder_md_table_wrap')

local M = {}

local MIN_COL = 3
local B = { -- rounded box-drawing pieces
  h = '─',
  v = '│',
  tl = '╭',
  tj = '┬',
  tr = '╮',
  ml = '├',
  mj = '┼',
  mr = '┤',
  bl = '╰',
  bj = '┴',
  br = '╯',
}

local function apply_hl()
  vim.api.nvim_set_hl(0, 'KinderTableBorder', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'KinderTableText', { fg = theme.fg })
end
apply_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })

local function strwidth(s) return vim.api.nvim_strwidth(s) end

local CHAR = '[%z\1-\127\194-\244][\128-\191]*'

-- The table's rows straight from the markdown tree, so quote markers, pipe-less rows
-- and escaped pipes need no parsing: each row's cells as byte ranges, plus alignments.
local function table_rows(parser, item)
  local r, c = item.range.row_start, item.range.col_start
  local node = parser:named_node_for_range({ r, c, r, c }, { ignore_injections = true })
  while node and node:type() ~= 'pipe_table' do node = node:parent() end
  if not node then return nil end

  local rows, aligns = {}, {}
  for child in node:iter_children() do
    local kind = child:type()
    if kind == 'pipe_table_header' or kind == 'pipe_table_row' then
      local cells = {}
      for cell in child:iter_children() do
        if cell:type() == 'pipe_table_cell' then
          local _, sc, _, ec = cell:range()
          cells[#cells + 1] = { sc, ec }
        end
      end
      rows[#rows + 1] = { row = child:start(), cells = cells }
    elseif kind == 'pipe_table_delimiter_row' then
      for cell in child:iter_children() do
        if cell:type() == 'pipe_table_delimiter_cell' then
          local left, right = false, false
          for mark in cell:iter_children() do
            left = left or mark:type() == 'pipe_table_align_left'
            right = right or mark:type() == 'pipe_table_align_right'
          end
          aligns[#aligns + 1] = left and right and 'center' or right and 'right' or 'left'
        end
      end
      rows[#rows + 1] = { row = child:start(), delimiter = true }
    end
  end
  return rows, aligns
end

-- markdown_inline roots by start row. Every cell is its own tree, and scanning all
-- trees of the buffer for each table dominated the render, so the index is rebuilt
-- only when the text or the set of parsed trees changes.
local inline_index = {}

-- Replayed cells per source row, keyed by the row's kind and text: the same bytes draw
-- the same, so a re-render only replays the rows that changed. Rows unused for a whole
-- changedtick drop out; table shapes are kept for one tick only.
local caches = {}

vim.api.nvim_create_autocmd('BufWipeout', {
  callback = function(args) inline_index[args.buf], caches[args.buf] = nil, nil end,
})

local function cache_for(buffer)
  local tick, cache = vim.b[buffer].changedtick, caches[buffer]
  if not cache then
    cache = { tick = tick, cur = {}, prev = {}, shapes = {} }
    caches[buffer] = cache
  elseif cache.tick ~= tick then
    if next(cache.cur) then cache.prev, cache.cur = cache.cur, {} end
    cache.tick, cache.shapes = tick, {}
  end
  return cache
end

local function inline_roots(buffer, parser, row_start, row_end)
  local ltree = parser:children().markdown_inline
  if not ltree then return {} end
  local trees, count = ltree:trees(), 0
  for _ in pairs(trees) do count = count + 1 end

  local tick, index = vim.b[buffer].changedtick, inline_index[buffer]
  if not index or index.tick ~= tick or index.count ~= count or index.ltree ~= ltree then
    index = { tick = tick, count = count, ltree = ltree, rows = {} }
    for _, tree in pairs(trees) do
      local root = tree:root()
      -- Plain text parses to a bare (inline) node, which no highlight pattern captures.
      if root:named_child_count() > 0 then
        local r = root:start()
        index.rows[r] = index.rows[r] or {}
        table.insert(index.rows[r], root)
      end
    end
    inline_index[buffer] = index
  end

  local roots = {}
  for r = row_start, row_end - 1 do vim.list_extend(roots, index.rows[r] or {}) end
  return roots
end

-- Everything that decides how nvim draws the table rows, per row: hl ranges and
-- conceals from the same highlight captures the treesitter highlighter applies, then
-- markview's inline marks (hl ranges, conceals, virtual text) on top of them.
local function decorations(buffer, parser, src, row_start, row_end, marks)
  local rows, order = {}, 0
  for r = row_start, row_end - 1 do rows[r] = { groups = {}, conceals = {}, inline = {} } end

  local function add(r, sc, ec, hl, conceal, priority)
    local line = rows[r]
    if not line or ec <= sc then return end
    order = order + 1
    if hl then line.groups[#line.groups + 1] = { sc, ec, hl, priority, order } end
    if conceal then line.conceals[#line.conceals + 1] = { sc, ec, conceal, priority, order } end
  end

  local function capture(lang, root)
    local query = vim.treesitter.query.get(lang, 'highlights')
    if not query then return end
    -- The cursor stops at (end_row, 0), so pass the exclusive end or the last row is lost.
    for id, node, metadata in query:iter_captures(root, buffer, row_start, row_end) do
      local name, m = query.captures[id], metadata[id]
      local sr, sc, er, ec
      if m and (m.range or m.offset) then
        local range = vim.treesitter.get_range(node, buffer, m)
        sr, sc, er, ec = range[1], range[2], range[4], range[5]
      else
        sr, sc, er, ec = node:range()
      end
      local priority = tonumber(metadata.priority or m and m.priority) or vim.hl.priorities.treesitter
      local conceal = metadata.conceal or m and m.conceal
      -- Same skips as the highlighter: private captures and spell markers draw nothing.
      local hl = not (name:sub(1, 1) == '_' or name == 'spell' or name == 'nospell')
        and ('@' .. name .. '.' .. lang) or nil
      local last = (ec == 0 and er > sr) and er - 1 or er
      for r = math.max(sr, row_start), math.min(last, row_end - 1) do
        add(r, r == sr and sc or 0, r == er and ec or math.huge, hl, conceal, priority)
      end
    end
  end
  for _, tree in pairs(parser:trees()) do capture(parser:lang(), tree:root()) end
  for _, root in ipairs(inline_roots(buffer, parser, row_start, row_end)) do capture('markdown_inline', root) end

  for _, m in ipairs(marks or {}) do
    local r, col, d = m[2], m[3], m[4]
    local line, priority = rows[r], d.priority or 4096
    if line and d.end_col and (d.end_row or r) == r then
      add(r, col, d.end_col, d.hl_group, d.conceal, priority)
    end
    if line and d.virt_text and d.virt_text_pos == 'inline' then
      line.inline[#line.inline + 1] = { col, d.virt_text }
    elseif line and d.virt_text and d.virt_text_pos == 'overlay' then
      -- An overlay hides as many cells as it draws.
      local text, cells, ec = src[r - row_start + 1] or '', 0, col
      for _, chunk in ipairs(d.virt_text) do cells = cells + strwidth(chunk[1]) end
      while cells > 0 and ec < #text do
        local ch = text:sub(ec + 1):match('^' .. CHAR) or text:sub(ec + 1, ec + 1)
        ec, cells = ec + #ch, cells - strwidth(ch)
      end
      add(r, col, ec, nil, '', priority)
      line.inline[#line.inline + 1] = { col, d.virt_text }
    end
  end

  local function by_priority(a, b)
    if a[4] ~= b[4] then return a[4] < b[4] end
    return a[5] < b[5]
  end
  for _, line in pairs(rows) do
    table.sort(line.groups, by_priority)
    table.sort(line.conceals, by_priority)
  end
  return rows
end

-- The decorations of a row that touch the cell [sc, ec), still in priority order.
local function slice(deco, sc, ec)
  local out = { groups = {}, conceals = {}, inline = {} }
  for _, g in ipairs(deco.groups) do
    if g[1] < ec and g[2] > sc then out.groups[#out.groups + 1] = g end
  end
  for _, c in ipairs(deco.conceals) do
    if c[1] < ec and c[2] > sc then out.conceals[#out.conceals + 1] = c end
  end
  for _, v in ipairs(deco.inline) do
    if v[1] >= sc and v[1] <= ec then out.inline[#out.inline + 1] = v end
  end
  return out
end

-- One cell's content as display units (words, runs of blanks, unbreakable virtual text),
-- built the way nvim draws its bytes: every covering hl stacked by priority, a concealed
-- run swapped for the replacement of its strongest conceal, inline virtual text in place.
local function cell_units(text, deco, sc, ec)
  local cols, seen = {}, {}
  local function cut(col)
    if col >= sc and col <= ec and not seen[col] then
      seen[col] = true
      cols[#cols + 1] = col
    end
  end
  cut(sc); cut(ec)
  for _, g in ipairs(deco.groups) do cut(g[1]); cut(g[2]) end
  for _, c in ipairs(deco.conceals) do cut(c[1]); cut(c[2]) end
  for _, v in ipairs(deco.inline) do cut(v[1]) end
  table.sort(cols)

  local units = {}
  local function width(s) return s:find('[\128-\255]') and strwidth(s) or #s end
  -- Virtual text and conceal replacements are glue: a line never breaks inside them.
  -- Control chars such as a tab become blanks; in a virtual line they draw wider than one cell.
  local function push(s, hl, glue)
    s = s:gsub('%c', ' ')
    if glue then
      units[#units + 1] = { text = s, hl = hl, width = width(s) }
      return
    end
    for gap, word in s:gmatch('(%s*)(%S*)') do
      if gap ~= '' then units[#units + 1] = { text = gap, hl = hl, width = #gap, space = true } end
      if word ~= '' then units[#units + 1] = { text = word, hl = hl, width = width(word) } end
    end
  end
  local function virt(col)
    for _, v in ipairs(deco.inline) do
      if v[1] == col then
        for _, chunk in ipairs(v[2]) do push(chunk[1], chunk[2] or 'KinderTableText', true) end
      end
    end
  end

  for i = 1, #cols - 1 do
    local col, stop = cols[i], cols[i + 1]
    virt(col)
    local hls = { 'KinderTableText' }
    for _, g in ipairs(deco.groups) do
      if col >= g[1] and col < g[2] then hls[#hls + 1] = g[3] end
    end
    local hidden
    for _, c in ipairs(deco.conceals) do
      if col >= c[1] and col < c[2] then hidden = c end
    end
    if not hidden then
      push(text:sub(col + 1, stop), hls)
    elseif col == math.max(hidden[1], sc) and hidden[3] ~= '' then
      push(hidden[3], hls, true)
    end
  end
  virt(ec)
  return units
end

-- Lines of at most `width` cells. Lines break only at blanks: a run of units with no
-- blank between them moves to the next line whole, and is cut by character only when
-- it is wider than the column on its own.
local function wrap_units(units, width)
  local lines, line, used, gap = {}, {}, 0, nil
  local function flush()
    lines[#lines + 1] = line
    line, used, gap = {}, 0, nil
  end
  local i = 1
  while i <= #units do
    if units[i].space then
      if used > 0 then gap = units[i] end
      i = i + 1
    else
      local j, run = i, 0
      while j <= #units and not units[j].space do
        run, j = run + units[j].width, j + 1
      end
      if used > 0 and used + (gap and gap.width or 0) + run > width then flush() end
      if used + (gap and gap.width or 0) + run <= width then
        if gap then line[#line + 1], used = gap, used + gap.width end
        for k = i, j - 1 do line[#line + 1] = units[k] end
        used, gap = used + run, nil
      else
        -- Pieces are fresh tables: the units themselves are cached and must stay intact.
        for k = i, j - 1 do
          for ch in units[k].text:gmatch(CHAR) do
            local w = ch:byte() < 0x80 and 1 or strwidth(ch)
            if used > 0 and used + w > width then flush() end
            local last = line[#line]
            if last and last.piece and last.hl == units[k].hl then
              last.text, last.width = last.text .. ch, last.width + w
            else
              line[#line + 1] = { text = ch, hl = units[k].hl, width = w, piece = true }
            end
            used = used + w
          end
        end
      end
      i = j
    end
  end
  if #line > 0 then flush() end
  return lines
end

-- Share the available text width across columns: start from natural widths,
-- clamp to a minimum, then trim the widest until the row fits.
local function distribute(cols_count, natural, available)
  local border_cost = 1 + cols_count * 3 -- one leading '|' plus ' | ' per column
  local budget = math.max(cols_count * MIN_COL, available - border_cost)
  local widths = {}
  for i = 1, cols_count do widths[i] = math.max(MIN_COL, natural[i]) end
  local function sum()
    local t = 0; for _, w in ipairs(widths) do t = t + w end; return t
  end
  while sum() > budget do
    local widest = 1
    for i = 2, cols_count do if widths[i] > widths[widest] then widest = i end end
    if widths[widest] <= MIN_COL then break end
    widths[widest] = widths[widest] - 1
  end
  return widths
end

-- Append one screen line of one cell to `chunks`, padded to the column, with units
-- that share an hl joined into one chunk.
local function cell_chunks(chunks, units, w, align)
  local used = 0
  for _, u in ipairs(units) do used = used + u.width end
  local missing = math.max(0, w - used)
  local left = align == 'right' and missing or align == 'center' and math.floor(missing / 2) or 0
  chunks[#chunks + 1] = { (' '):rep(left + 1), 'KinderTableText' }
  local open
  for _, u in ipairs(units) do
    if open and open[2] == u.hl then
      open[1] = open[1] .. u.text
    else
      open = { u.text, u.hl }
      chunks[#chunks + 1] = open
    end
  end
  chunks[#chunks + 1] = { (' '):rep(missing - left + 1), 'KinderTableText' }
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

-- One source row (per-column units) -> its wrapped virt lines.
local function row_lines(cells, widths, aligns)
  local wrapped, height = {}, 1
  for i = 1, #widths do
    wrapped[i] = wrap_units(cells[i] or {}, widths[i])
    height = math.max(height, #wrapped[i])
  end
  local out = {}
  for line = 1, height do
    local chunks = { { B.v, 'KinderTableBorder' } }
    for i = 1, #widths do
      cell_chunks(chunks, wrapped[i][line] or {}, widths[i], aligns[i])
      chunks[#chunks + 1] = { B.v, 'KinderTableBorder' }
    end
    out[#out + 1] = chunks
  end
  return out
end

-- Rendered lines grouped by the source row they belong to: the header row also
-- carries the top border, the delimiter row the middle one, the last row the bottom one.
local function build(buffer, item, src, inline_marks, width)
  local row_start, row_end = item.range.row_start, item.range.row_end
  local cache, parser = cache_for(buffer), nil
  local function parsed()
    if parser == nil then
      local ok, p = pcall(vim.treesitter.get_parser, buffer, 'markdown')
      parser = ok and p or false
      if parser then parser:parse({ row_start, 0, row_end, 0 }) end
    end
    return parser
  end

  local key = ('%d:%d:%d'):format(row_start, item.range.col_start, row_end)
  local shape = cache.shapes[key]
  if not shape then
    if not parsed() then return nil end
    local rows, aligns = table_rows(parser, item)
    if not rows or not rows[1] or rows[1].delimiter or #rows[1].cells == 0 then return nil end
    shape = { rows = rows, aligns = aligns }
    cache.shapes[key] = shape
  end
  local rows, aligns, cols = shape.rows, shape.aligns, #shape.rows[1].cells

  local deco
  local cells, natural = {}, {}
  for i = 1, cols do natural[i] = 0 end
  for k, row in ipairs(rows) do
    if not row.delimiter then
      local text = src[row.row - row_start + 1] or ''
      local id = (k == 1 and 'h' or 'd') .. text
      local units = cache.cur[id] or cache.prev[id]
      if not units then
        if not deco then
          if not parsed() then return nil end
          deco = decorations(buffer, parser, src, row_start, row_end,
            inline_marks and inline_marks(buffer, row_start, row_end))
        end
        units = { widths = {} }
        for i, range in ipairs(row.cells) do
          -- A cell node keeps the blanks before its closing pipe; an empty one is all blanks.
          local raw = text:sub(range[1] + 1, range[2])
          local sc = range[1] + #raw:match('^%s*')
          local ec, w = math.max(sc, range[2] - #raw:match('%s*$')), 0
          units[i] = cell_units(text, slice(deco[row.row], sc, ec), sc, ec)
          for _, u in ipairs(units[i]) do w = w + u.width end
          units.widths[i] = w
        end
      end
      cache.cur[id], cells[k] = units, units
      for i = 1, cols do natural[i] = math.max(natural[i], units.widths[i] or 0) end
    end
  end

  local widths = distribute(cols, natural, width)
  local groups = {}
  for k, row in ipairs(rows) do
    groups[row.row - row_start + 1] = row.delimiter and { border(B.ml, B.mj, B.mr, widths) }
      or row_lines(cells[k], widths, aligns)
  end
  table.insert(groups[rows[1].row - row_start + 1], 1, border(B.tl, B.tj, B.tr, widths))
  local last = groups[rows[#rows].row - row_start + 1]
  last[#last + 1] = border(B.bl, B.bj, B.br, widths)
  return groups
end

-- Width the wrapped continuations of a source row lose to 'breakindent'/'showbreak';
-- the whole box is shifted by it so anchor overlays stay column-aligned.
local function break_indent(line, avail, win)
  local sbr = vim.wo[win].showbreak
  if sbr == '' then sbr = vim.o.showbreak end
  local extra = strwidth(sbr or '')
  if not vim.wo[win].breakindent then return extra end
  local shift, minw = 0, 20
  for opt in (vim.wo[win].breakindentopt or ''):gmatch('[^,]+') do
    local k, v = opt:match('^(%a+):(%-?%d+)$')
    local num = tonumber(v) or 0
    if k == 'shift' then shift = num elseif k == 'min' then minw = num end
  end
  local bri = math.max(0, strwidth(line:match('^%s*') or '') + shift) + extra
  if avail - bri < minw then bri = math.max(0, avail - minw) end
  return bri
end

-- Byte offset where each screen row of `line` starts under 'wrap'. Mirrors nvim's
-- own 'linebreak' rule (win_lbr_chartabsize): the last space before a word is
-- stretched to the row's end when the word plus its trailing spaces would not fit,
-- which is why padded table rows break far short of the text width. No API exposes
-- this: win_text_height's vcol range ignores linebreak, screenpos only answers for
-- rows currently on screen.
local function wrap_starts(line, avail, win)
  local lbr = vim.wo[win].linebreak
  local bri = break_indent(line, avail, win)
  local brk = {}
  if lbr then for c in vim.o.breakat:gmatch('.') do brk[c] = true end end
  local n = #line

  local function char_at(k)
    local b = line:byte(k)
    local len = b < 0x80 and 1 or (b < 0xE0 and 2 or (b < 0xF0 and 3 or 4))
    local ch = line:sub(k, k + len - 1)
    return ch, len, b < 0x80 and 1 or strwidth(ch)
  end

  -- Walk the word that follows a breakat char, then its trailing spaces, stopping
  -- where the next word starts; true when that run crosses the row's end.
  local function overflows(k, col, width)
    local col2, prev_brk, first = col, true, true
    while k <= n do
      local ch, len, w = char_at(k)
      local isb = brk[ch] or false
      if not (isb or first or not prev_brk) then return false end
      col2 = col2 + w
      if col2 >= width then return true end
      first, prev_brk, k = false, isb, k + len
    end
    return false
  end

  local starts, i, row = { 0 }, 1, 0
  while i <= n do
    local width = math.max(1, row == 0 and avail or avail - bri)
    local used, j, stretched = 0, i, nil
    while j <= n do
      local ch, len, w = char_at(j)
      if used + w > width then break end
      if lbr and brk[ch] and j + len <= n and not brk[(char_at(j + len))] then
        if overflows(j + len, used, width) and j + len > i then
          stretched = j + len
          break
        end
      end
      used, j = used + w, j + len
    end
    local nxt = stretched or j
    if not stretched and j > n then break end
    starts[#starts + 1] = nxt - 1
    i, row = nxt, row + 1
  end
  return starts
end

-- Quote markers ahead of a quoted table's first column, taken from markview's own
-- overlays on that row, so every box line keeps the quote bar. Returns chunks, width.
local function quote_prefix(buffer, row, from, to)
  if to <= from then return {}, 0 end
  local line = vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or ''
  local mv = vim.api.nvim_get_namespaces()['markview/markdown']
  local overlays = {}
  if mv then
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buffer, mv, { row, from }, { row, to - 1 }, { details = true })) do
      if m[4].virt_text_pos == 'overlay' and m[4].virt_text then overlays[m[3]] = m[4].virt_text end
    end
  end
  local chunks, width, col = {}, 0, from
  while col < to do
    local w, vt = 0, overlays[col]
    if vt then
      for _, c in ipairs(vt) do
        chunks[#chunks + 1] = { c[1], c[2] or 'KinderTableText' }; w = w + strwidth(c[1])
      end
    else
      local ch = line:sub(col + 1, col + 1)
      chunks[#chunks + 1] = { ch, 'KinderTableText' }; w = strwidth(ch)
    end
    width, col = width + w, col + math.max(1, w)
  end
  return chunks, width
end

-- Clear this module's marks over the table, plus the anchor rows just outside it
-- (a leading virt_lines block hangs on row_start-1 or row_end, not inside the range).
function M.clear(buffer, item)
  local from = math.max(0, item.range.row_start - 1)
  vim.api.nvim_buf_clear_namespace(buffer, ns, from, item.range.row_end + 1)
end

-- Row-range clear for markview's own lifecycle (insert mode, disable) - see markdown.lua.
function M.clear_range(buffer, from, to)
  vim.api.nvim_buf_clear_namespace(buffer, ns, from, to)
end

-- `inline_marks(buffer, from, to)` returns the extmark details markview's inline pass
-- would place on rows [from, to), for the cells to replay.
function M.render(buffer, item, win, inline_marks)
  M.clear(buffer, item)
  local row_start, row_end = item.range.row_start, item.range.row_end

  local textoff = vim.fn.getwininfo(win)[1].textoff
  local avail = math.max(20, vim.api.nvim_win_get_width(win) - textoff)
  local src = vim.api.nvim_buf_get_lines(buffer, row_start, row_end, false)
  if #src == 0 then return end

  local indent = break_indent(src[1], avail, win)
  -- Leading blanks already come back through 'breakindent'; the rest is quote markers.
  local prefix, prefix_w = quote_prefix(buffer, row_start, #src[1]:match('^%s*'), item.range.col_start)
  local groups = build(buffer, item, src, inline_marks, avail - indent - prefix_w)
  if not groups then return end

  -- Continuation screen rows already start past the break indent, so only the first
  -- screen row and hanging virt_lines take the pad; every line takes the quote prefix.
  local pad = indent > 0 and { (' '):rep(indent), 'KinderTableText' } or nil
  local function shifted(line, padded)
    local out = (padded and pad) and { pad } or {}
    vim.list_extend(out, prefix)
    return vim.list_extend(out, line)
  end

  -- An overlay only hides what it covers, so a box narrower than the text area
  -- would leave the raw tail of the row showing to its right.
  local box = 0
  for _, c in ipairs(groups[1][1]) do box = box + strwidth(c[1]) end
  local tail = avail - indent - prefix_w - box
  local function filled(line)
    if tail <= 0 then return line end
    local out = vim.list_extend({}, line)
    out[#out + 1] = { (' '):rep(tail), 'KinderTableText' }
    return out
  end

  local starts = {}
  for i = 1, #src do starts[i] = wrap_starts(src[i], avail, win) end

  -- Extmarks belong to the buffer, so one buffer shown in two windows of different
  -- width would leave the overlays valid in only one; hang the box off a single
  -- anchor there instead, as before.
  local shared = false
  for _, w in ipairs(vim.fn.win_findbuf(buffer)) do
    if w ~= win and vim.wo[w].wrap and vim.api.nvim_win_get_width(w) - vim.fn.getwininfo(w)[1].textoff ~= avail then
      shared = true
      break
    end
  end

  -- Lines still to come from row k on, so a row only takes the anchor role when
  -- enough of them are left to cover its own screen rows.
  local left, acc = {}, 0
  for k = #src, 1, -1 do
    acc = acc + #(groups[k] or {}); left[k] = acc
  end

  -- Every source row becomes its own anchor unless it is still needed to pay off
  -- the previous anchor's overlay debt; those rows collapse to zero height. Each
  -- anchor is a separate scroll stop, which a single virt_lines block never is:
  -- 'topfill' caps at the window height, hiding the middle of a tall block.
  local segs = { { anchor = nil, need = 0, lines = {} } }
  for k = 1, #src do
    local row, cur = row_start + k - 1, segs[#segs]
    local h = #starts[k]
    if not shared and #cur.lines >= cur.need and #(groups[k] or {}) > 0 and left[k] >= h then
      segs[#segs + 1] = { anchor = row, index = k, need = h, lines = {} }
      cur = segs[#segs]
    else
      vim.api.nvim_buf_set_extmark(buffer, ns, row, 0, { conceal_lines = '' })
    end
    vim.list_extend(cur.lines, groups[k] or {})
  end

  -- nvim never scrolls past the buffer's last row, so virt_lines hung under it stay
  -- off-screen. That anchor keeps the tail of its box and spills the head one segment up.
  local tail_seg = segs[#segs]
  local spill = tail_seg.anchor == vim.api.nvim_buf_line_count(buffer) - 1
      and #tail_seg.lines - tail_seg.need or 0
  if spill > 0 then
    local prev, kept = segs[#segs - 1], {}
    for i = 1, #tail_seg.lines do
      if i <= spill then prev.lines[#prev.lines + 1] = tail_seg.lines[i] else kept[#kept + 1] = tail_seg.lines[i] end
    end
    tail_seg.lines = kept
  end

  for _, seg in ipairs(segs) do
    local rest, from = {}, seg.anchor and seg.need + 1 or 1
    for i = from, #seg.lines do rest[#rest + 1] = shifted(seg.lines[i], true) end

    if seg.anchor then
      -- The row's own screen rows carry the first lines as overlays; only what
      -- does not fit hangs below as virtual lines.
      for i = 1, math.min(seg.need, #seg.lines) do
        vim.api.nvim_buf_set_extmark(buffer, ns, seg.anchor, starts[seg.index][i] or 0, {
          virt_text = filled(shifted(seg.lines[i], i == 1)),
          virt_text_pos = 'overlay',
          priority = 5000,
        })
      end
      if #rest > 0 then
        vim.api.nvim_buf_set_extmark(buffer, ns, seg.anchor, 0, { virt_lines = rest })
      end
    elseif #rest > 0 then
      -- Nothing anchored yet: hang the block off the row outside the table.
      if row_start > 0 then
        vim.api.nvim_buf_set_extmark(buffer, ns, row_start - 1, 0, { virt_lines = rest })
      elseif row_end < vim.api.nvim_buf_line_count(buffer) then
        vim.api.nvim_buf_set_extmark(buffer, ns, row_end, 0, { virt_lines = rest, virt_lines_above = true })
      end
    end
  end
end

return M
