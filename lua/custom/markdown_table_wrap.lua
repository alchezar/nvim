-- Word-wrapped markdown tables under 'wrap': long cells break inside the column
-- instead of dragging the row off-screen. The box is split into per-row segments
-- anchored on the source rows themselves, so a tall table stays scrollable.

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

-- Italic and strike set no fg, so they stack over the bold or link color.
local function apply_hl()
  vim.api.nvim_set_hl(0, 'KinderTableBorder', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'KinderTableText', { fg = theme.fg })
  vim.api.nvim_set_hl(0, 'KinderTableBold', { fg = theme.teal, bold = true })
  vim.api.nvim_set_hl(0, 'KinderTableItalic', { italic = true })
  vim.api.nvim_set_hl(0, 'KinderTableStrike', { strikethrough = true })
  vim.api.nvim_set_hl(0, 'KinderTableLink', { fg = theme.blue })
end
apply_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })

local function strwidth(s) return vim.api.nvim_strwidth(s) end

-- Split cell text into styled segments, dropping the markup punctuation itself:
-- `code`, **bold**, *italic*, ~~strike~~, [label](url) and \ escapes. All but code
-- nest, so inner text is parsed again with its hl stacked on the outer ones.
-- Order matters - test *** before ** before *.
local function parse_inline(text, hls, segs)
  hls, segs = hls or { 'KinderTableText' }, segs or {}
  local plain, i = {}, 1
  local function flush()
    if #plain > 0 then
      segs[#segs + 1] = { text = table.concat(plain), hl = hls }; plain = {}
    end
  end
  local function nest(inner, ...)
    flush()
    parse_inline(inner, vim.list_extend(vim.list_extend({}, hls), { ... }), segs)
  end
  while i <= #text do
    local rest = text:sub(i)
    local esc = rest:match('^\\(%p)')
    local code = rest:match('^`([^`]+)`')
    local both = rest:match('^%*%*%*(.-)%*%*%*')
    local bold = rest:match('^%*%*(.-)%*%*')
    local strike = rest:match('^~~(.-)~~')
    local lbl, url = rest:match('^%[([^%]]*)%]%(([^)]*)%)')
    -- The closing * must not touch another *, or "*a **b** c*" would end inside the **.
    local em = rest:match('^%*([^%s%*].-[^%s%*])%*%f[^%*]') or rest:match('^%*([^%s%*])%*%f[^%*]')
    if esc then
      plain[#plain + 1] = esc; i = i + 2
    elseif code then
      flush()
      segs[#segs + 1] = { text = code, hl = vim.list_extend(vim.list_extend({}, hls), { 'KinderMarkdownInlineCode' }) }
      i = i + #code + 2
    elseif both and #both > 0 then
      nest(both, 'KinderTableBold', 'KinderTableItalic'); i = i + #both + 6
    elseif bold and #bold > 0 then
      nest(bold, 'KinderTableBold'); i = i + #bold + 4
    elseif strike and #strike > 0 then
      nest(strike, 'KinderTableStrike'); i = i + #strike + 4
    elseif lbl then
      nest(lbl, 'KinderTableLink'); i = i + #lbl + #url + 4
    elseif em then
      nest(em, 'KinderTableItalic'); i = i + #em + 2
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

-- Segments -> words, each a list of styled pieces. A word can span segments, as in
-- "**bold**,", so wrapping never breaks it or puts a space inside it.
local function tokenize(segs)
  local words, word = {}, nil
  for _, s in ipairs(segs) do
    for gap, run in s.text:gmatch('(%s*)(%S*)') do
      if gap ~= '' then word = nil end
      if run ~= '' then
        if not word then
          word = {}; words[#words + 1] = word
        end
        word[#word + 1] = { text = run, hl = s.hl }
      end
    end
  end
  return words
end

local function word_width(word)
  local w = 0
  for _, p in ipairs(word) do w = w + strwidth(p.text) end
  return w
end

-- Greedy word wrap to a display-width limit; each screen line is a word list.
-- A word wider than the limit is split by character, keeping each piece's hl.
local function wrap_words(words, limit)
  if limit < 1 then limit = 1 end
  local lines, cur, curw = {}, {}, 0
  local function flush()
    lines[#lines + 1] = cur; cur, curw = {}, 0
  end
  for _, word in ipairs(words) do
    local ww = word_width(word)
    if ww > limit then
      if curw > 0 then flush() end
      local piece, pw = {}, 0
      for _, p in ipairs(word) do
        for ch in p.text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
          local chw = strwidth(ch)
          if pw > 0 and pw + chw > limit then
            lines[#lines + 1] = { piece }; piece, pw = {}, 0
          end
          local last = piece[#piece]
          if last and last.hl == p.hl then
            last.text = last.text .. ch
          else
            piece[#piece + 1] = { text = ch, hl = p.hl }
          end
          pw = pw + chw
        end
      end
      if pw > 0 then cur, curw = { piece }, pw end
    else
      local add = curw == 0 and ww or (curw + 1 + ww)
      if curw > 0 and add > limit then
        flush(); add = ww
      end
      cur[#cur + 1] = word; curw = add
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

-- One screen line of one cell -> chunk list " word word …" padded to the column.
local function cell_chunks(words, w, align)
  local chunks, used = {}, 0
  for i, word in ipairs(words) do
    if i > 1 then
      chunks[#chunks + 1] = { ' ', 'KinderTableText' }; used = used + 1
    end
    for _, p in ipairs(word) do
      chunks[#chunks + 1] = { p.text, p.hl }; used = used + strwidth(p.text)
    end
  end
  local missing = math.max(0, w - used)
  local left, right = 0, missing
  if align == 'right' then
    left, right = missing, 0
  elseif align == 'center' then
    left = math.floor(missing / 2); right = missing - left
  end
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
    wrapped[i] = wrap_words(tokenize(cells[i] or {}), widths[i])
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

-- Rendered lines grouped by the source row they belong to: the header row also
-- carries the top border, the last data row the bottom one.
local function build(item, width)
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

  local widths = distribute(cols, natural, width)
  local groups = { { border(B.tl, B.tj, B.tr, widths) } }
  vim.list_extend(groups[1], row_lines(header, widths, aligns))
  groups[2] = { border(B.ml, B.mj, B.mr, widths) }
  for _, row in ipairs(data) do groups[#groups + 1] = row_lines(row, widths, aligns) end
  local last = groups[#groups]
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

function M.render(buffer, item, win)
  M.clear(buffer, item)
  local row_start, row_end = item.range.row_start, item.range.row_end

  local textoff = vim.fn.getwininfo(win)[1].textoff
  local avail = math.max(20, vim.api.nvim_win_get_width(win) - textoff)
  local src = vim.api.nvim_buf_get_lines(buffer, row_start, row_end, false)
  if #src == 0 then return end

  local indent = break_indent(src[1], avail, win)
  -- Leading blanks already come back through 'breakindent'; the rest is quote markers.
  local prefix, prefix_w = quote_prefix(buffer, row_start, #src[1]:match('^%s*'), item.range.col_start)
  local groups = build(item, avail - indent - prefix_w)
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
