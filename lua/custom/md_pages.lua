-- Approximate A4 page count for markdown buffers, shown in fishbone's
-- statusline. Lines are word-wrapped to the printable width first, so a file of
-- few but very long lines still costs the pages it would really print.

-- Text area of A4 (210x297mm) with 20mm margins at ~11pt: 170mm / ~1.9mm per
-- glyph and 257mm / ~4.7mm per line.
local chars_per_line = 90
local lines_per_page = 54

-- Join soft-wrapped lines back into one paragraph before wrapping, the way a
-- markdown renderer does. Off: every buffer line costs at least one printed
-- line, which inflates the count for files hard-wrapped at textwidth.
local reflow_paragraphs = true

local ICON = '\u{f0219}' -- 󰈙 same glyph the file tree uses for .txt

local M = {}

-- Codepoints, not bytes: continuation bytes (0x80-0xBF) don't add width.
local function char_width(s)
  local stripped = s:gsub('[\128-\191]', '')
  return #stripped
end

-- Greedy word wrap; a word longer than the line breaks mid-word, as print does.
local function visual_lines(line)
  local w = char_width(line)
  if w <= chars_per_line then return 1 end

  local rows, used = 1, 0
  for word in line:gmatch('%S+') do
    local ww = char_width(word)
    if used == 0 then
      used = ww
    elseif used + 1 + ww <= chars_per_line then
      used = used + 1 + ww
    else
      rows = rows + 1
      used = ww
    end
    while used > chars_per_line do
      rows = rows + 1
      used = used - chars_per_line
    end
  end
  return rows
end

-- Lines that start their own block and so never merge with the line above.
local function starts_block(line)
  return line:match('^%s*$') ~= nil
      or line:match('^%s*[-*+]%s') ~= nil    -- bullet list
      or line:match('^%s*%d+[.)]%s') ~= nil  -- ordered list
      or line:match('^#') ~= nil             -- heading
      or line:match('^%s*>') ~= nil          -- quote
      or line:match('^%s*|') ~= nil          -- table row
      or line:match('^    ') ~= nil          -- indented code
      or line:match('^\t') ~= nil
end

-- render() runs on every CursorMoved, so keep the sweep per changedtick.
local cache = {}

local function page_count(bufnr)
  local tick = vim.b[bufnr].changedtick
  local hit = cache[bufnr]
  if hit and hit.tick == tick then return hit.pages end

  local rows, para, in_fence = 0, nil, false
  local function flush()
    if para then
      rows = rows + visual_lines(para)
      para = nil
    end
  end

  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:match('^%s*```') or line:match('^%s*~~~') then
      flush()
      in_fence = not in_fence
      rows = rows + 1
    elseif reflow_paragraphs and not in_fence and not starts_block(line) then
      para = para and (para .. ' ' .. line) or line
    else
      flush()
      rows = rows + visual_lines(line)
    end
  end
  flush()

  local pages = math.max(1, math.ceil(rows / lines_per_page))

  cache[bufnr] = { tick = tick, pages = pages }
  return pages
end

local BAR_OPEN = '%@FishboneClick@'
local BAR_CLOSE = '%X'

-- Right after the scrollbar's clickable region, i.e. left of the diagnostics
-- block. Nil when fishbone drew no bar (window too narrow).
local function insert_after_bar(rendered, segment)
  local _, open_end = rendered:find(BAR_OPEN, 1, true)
  local close_start = open_end and rendered:find(BAR_CLOSE, open_end, true)
  if not close_start then return nil end

  local cut = close_start + #BAR_CLOSE - 1
  return rendered:sub(1, cut) .. segment .. rendered:sub(cut + 1)
end

-- fishbone sizes its bar as `columns - left - right`, so hiding part of
-- `columns` from it makes the bar itself give up the room - and its click
-- geometry keeps matching the bar it actually drew.
local reserve = 0
local real_o = vim.o
local narrow_o = setmetatable({}, {
  __index = function(_, k)
    if k == 'columns' then return real_o.columns - reserve end
    return real_o[k]
  end,
  __newindex = function(_, k, v) real_o[k] = v end,
})

local fishbone = require('fishbone')
local orig_render = fishbone.render

fishbone.render = function()
  local bufnr = vim.api.nvim_win_get_buf(0)
  if not vim.bo[bufnr].filetype:match('markdown') then return orig_render() end

  local plain = '  ' .. ICON .. ' ' .. tostring(page_count(bufnr))
  reserve = vim.fn.strdisplaywidth(plain)

  vim.o = narrow_o
  local ok, rendered = pcall(orig_render)
  vim.o = real_o
  if not ok then error(rendered) end

  return insert_after_bar(rendered, '%#FbnInfoTxt#' .. plain) or rendered
end

vim.api.nvim_create_autocmd('BufDelete', {
  group = vim.api.nvim_create_augroup('MdPages', { clear = true }),
  callback = function(args) cache[args.buf] = nil end,
})

-- Exposed for tuning the constants: `:lua print(require('custom.md_pages').pages())`
function M.pages(bufnr)
  if not bufnr or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  return page_count(bufnr)
end

return M
