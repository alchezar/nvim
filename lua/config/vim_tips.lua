-- Vim motion/command tips for the startify cow balloon, parsed live from the
-- bundled `:help index` (doc/index.txt) so the pool tracks the running Neovim
-- version instead of being hardcoded. Each tip becomes a two-line startify
-- quote padded to a common width so the cow speaks the key in the top-left and
-- its description in the bottom-right corner of the bubble:
--   { 'ciw                 ', '   change inner word' }
-- The cowsay header picks one at random alongside the regular quotes.

local M = {}

-- Sections of index.txt worth surfacing; Ex/Terminal/Command-line are skipped
-- as they read more like a command catalogue than memorable motions.
local WANTED_SECTIONS = {
  ['insert-index'] = true,
  ['normal-index'] = true,
  ['visual-index'] = true,
}

-- Descriptions matching these are noise ("same as h", "not used", ...).
local SKIP_PATTERNS = {
  'not used', 'same as', 'reserved', 'nothing', 'interrupt',
  'redraw', 'suspend', 'no%-op', 'not mapped',
}

-- Arrow/navigation/mouse keys are dull tips and steer away from real motions.
local SKIP_CHARS = {
  'Left', 'Right', 'Up', 'Down', 'Home', 'End', 'Page',
  'Mouse', 'Insert', 'Del', 'BS', 'Help', 'Undo', 'k%u',
}

-- Startify's boxed() wraps any line past column 50, which would break the
-- two-line alignment; cap the padded width below that.
local MAX_WIDTH = 48

local function is_noise(desc)
  for _, pat in ipairs(SKIP_PATTERNS) do
    if desc:lower():find(pat) then return true end
  end
  return false
end

local function is_dull_char(char)
  for _, pat in ipairs(SKIP_CHARS) do
    if char:find(pat) then return true end
  end
  return false
end

-- The description uses a bare `N`/`Nth`/`Nmove` for the optional count prefix.
local function takes_count(desc)
  for w in desc:gmatch('%a+') do
    if w == 'N' or w == 'Nth' or w == 'Nmove' then return true end
  end
  return false
end

-- Prefix a literal `N` so the count's place in the typed command is explicit
-- (`][` -> `N][`). Skip CTRL-/<key>/already-counted chars where it reads badly.
local function with_count(char, desc)
  if not takes_count(desc) then return char end
  if char:match('^[N{]') or char:find('CTRL') or char:match('^<') then return char end
  return 'N' .. char
end

-- An entry line: `|tag|<ws>CHAR<cols>[note]  description`. Columns are tab- or
-- 2+-space aligned, so normalize tabs to a double space and split on any 2+
-- space gap. The char keeps single-space runs (e.g. `CTRL-W {char}`); a lone
-- `1`/`2` note column between char and description is dropped. The description
-- may be empty here and continue on following indented lines.
local function parse_entry(line)
  local body = line:match('^|[^|]*|(.*)')
  if not body then return nil end
  body = body:gsub('\t', '  '):gsub('^%s+', '')
  local cols = {}
  for seg in (body .. '  '):gmatch('(.-)%s%s+') do
    if seg ~= '' then cols[#cols + 1] = seg end
  end
  if not cols[1] then return nil end
  local first_desc = (cols[2] == '1' or cols[2] == '2') and 3 or 2
  return cols[1], table.concat(cols, ' ', first_desc)
end

-- Finalize a record into a two-line, width-padded startify quote (key top-left,
-- description bottom-right), or nil if it fails the filters.
local function finalize(rec)
  if not rec then return nil end
  local desc = rec.desc:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  -- A `"` ditto mark (or any letter-less line) is not a real description.
  if not desc:match('%a') then return nil end
  if is_noise(desc) or is_dull_char(rec.char) then return nil end
  local char = with_count(rec.char, desc)
  -- Pad to char + desc + a gap so the bubble is wider than either line: the key
  -- stays flush left on top, the description flush right on the bottom.
  local width = #char + #desc + 4
  if width > MAX_WIDTH then return nil end
  local top = char .. string.rep(' ', width - #char)
  local bot = string.rep(' ', width - #desc) .. desc
  return { top, bot }
end

-- Build the quote list. Indented, tagless lines continue the current record's
-- description so each tip is self-contained rather than cut mid-sentence.
local function build()
  local files = vim.api.nvim_get_runtime_file('doc/index.txt', false)
  if not files[1] then return {} end
  local ok, lines = pcall(vim.fn.readfile, files[1])
  if not ok then return {} end

  local tips, active, rec = {}, false, nil
  local function flush()
    local tip = finalize(rec)
    if tip then tips[#tips + 1] = tip end
    rec = nil
  end

  for _, line in ipairs(lines) do
    local sec = line:match('%*([%w%-]+%-index)%*')
    if sec then
      flush()
      active = WANTED_SECTIONS[sec] == true
    elseif active and line:match('^|') then
      flush()
      local char, desc = parse_entry(line)
      if char then rec = { char = char, desc = desc } end
    elseif active and rec and line:match('^%s+%S') then
      rec.desc = rec.desc .. ' ' .. line:gsub('^%s+', '')
    elseif line:match('^%s*$') then
      flush()
    end
  end
  flush()
  return tips
end

local cache

-- Memoized so the parse runs once per session.
function M.get()
  if not cache then cache = build() end
  return cache
end

return M
