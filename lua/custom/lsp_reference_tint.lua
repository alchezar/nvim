-- References take the colour of the symbol under the cursor, like the cursor
-- itself, but muted: light colours move most of the way to the editor bg, dark
-- ones to fg and get black text, since dark-on-dark vanishes.

local theme = require('config.theme_colors')
local util = vim.lsp.util
local Kind = vim.lsp.protocol.DocumentHighlightKind

local ns = vim.api.nvim_create_namespace('nvim.lsp.references')
-- Relative luminance below which a colour counts as dark (silver, brown, dark).
local DARK_LUM = 0.2
-- How far a light colour moves towards bg (2/3 keeps a third of it); dark ones
-- move less towards fg, a full lift reads as glare.
local MUTE = 2 / 3
local LIFT = 1 / 3

local function rgb(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

local function luminance(hex)
  local out = {}
  for _, c in ipairs({ rgb(hex) }) do
    c = c / 255
    out[#out + 1] = c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * out[1] + 0.7152 * out[2] + 0.0722 * out[3]
end

local function mix(a, b, t)
  local ar, ag, ab = rgb(a)
  local br, bg, bb = rgb(b)
  return string.format('#%02X%02X%02X',
    math.floor(ar + (br - ar) * t + 0.5), math.floor(ag + (bg - ag) * t + 0.5), math.floor(ab + (bb - ab) * t + 0.5))
end

-- Mirrors nvim's capture lookup: `@a.b.lang` falls back to `@a.b`, then `@a`.
local function group_fg(name)
  while name do
    local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
    if hl.fg then return hl.fg end
    if next(hl) ~= nil then return nil end
    name = name:match('^(.*)%.[^.]+$')
  end
end

-- Effective foreground at a position: the highest-priority layer that sets one wins.
local function fg_at(bufnr, row, col)
  local items = vim.inspect_pos(bufnr, row, col, { syntax = false, extmarks = false })
  local layers = {}
  for _, t in ipairs(items.treesitter) do
    local prio = tonumber(t.metadata and t.metadata.priority) or vim.hl.priorities.treesitter
    layers[#layers + 1] = { prio = prio, order = #layers, name = t.hl_group }
  end
  for _, s in ipairs(items.semantic_tokens) do
    layers[#layers + 1] = { prio = s.opts.priority, order = #layers, name = s.opts.hl_group }
  end
  table.sort(layers, function(a, b)
    if a.prio ~= b.prio then return a.prio > b.prio end
    return a.order > b.order
  end)
  for _, l in ipairs(layers) do
    local fg = group_fg(l.name)
    if fg then return string.format('#%06X', fg) end
  end
end

local function byte_col(bufnr, pos, encoding)
  local line = vim.api.nvim_buf_get_lines(bufnr, pos.line, pos.line + 1, false)[1] or ''
  return vim.str_byteindex(line, encoding, pos.character, false)
end

-- One group per kind per symbol colour, made on first use; `hi clear` drops them.
local groups = {}
vim.api.nvim_create_autocmd('ColorScheme', { callback = function() groups = {} end })

local function groups_for(fg)
  if groups[fg] then return groups[fg] end
  local dark = luminance(fg) < DARK_LUM
  local bg = dark and mix(fg, theme.fg, LIFT) or mix(fg, theme.bg, MUTE)
  local text = dark and theme.black or nil
  local set = {}
  for kind, name in pairs({ [Kind.Text] = 'Text', [Kind.Read] = 'Read', [Kind.Write] = 'Write' }) do
    local group = 'KinderLspReference' .. name .. fg:sub(2)
    vim.api.nvim_set_hl(0, group, { bg = bg, fg = text, bold = kind == Kind.Write or nil })
    set[kind] = group
  end
  groups[fg] = set
  return set
end

---@diagnostic disable-next-line: duplicate-set-field
util.buf_highlight_references = function(bufnr, references, encoding)
  if #references == 0 then return end
  local fg
  if bufnr == vim.api.nvim_get_current_buf() then
    local cur = vim.api.nvim_win_get_cursor(0)
    fg = fg_at(bufnr, cur[1] - 1, cur[2])
  end
  if not fg then
    local s = references[1].range.start
    fg = fg_at(bufnr, s.line, byte_col(bufnr, s, encoding))
  end
  local set = groups_for(fg or theme.fg)
  for _, ref in ipairs(references) do
    local s, e = ref.range.start, ref.range['end']
    vim.hl.range(bufnr, ns, set[ref.kind or Kind.Text],
      { s.line, byte_col(bufnr, s, encoding) }, { e.line, byte_col(bufnr, e, encoding) },
      { priority = vim.hl.priorities.user })
  end
end
