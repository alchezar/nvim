-- Document-highlight references share their background with `dark` text
-- (attributes, modules, namespaces), which makes that text vanish. Route
-- references whose text is painted `dark` through groups with a black foreground.

local theme = require('config.theme_colors')
local util = vim.lsp.util

local ns = vim.api.nvim_create_namespace('nvim.lsp.references')
local dark = tonumber(theme.dark:sub(2), 16)

local kind_group = {
  [vim.lsp.protocol.DocumentHighlightKind.Text] = 'LspReferenceTextDark',
  [vim.lsp.protocol.DocumentHighlightKind.Read] = 'LspReferenceReadDark',
  [vim.lsp.protocol.DocumentHighlightKind.Write] = 'LspReferenceWriteDark',
}

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
    if fg then return fg end
  end
end

local function byte_col(bufnr, pos, encoding)
  local line = vim.api.nvim_buf_get_lines(bufnr, pos.line, pos.line + 1, false)[1] or ''
  return vim.str_byteindex(line, encoding, pos.character, false)
end

local plain_highlight = util.buf_highlight_references
---@diagnostic disable-next-line: duplicate-set-field
util.buf_highlight_references = function(bufnr, references, encoding)
  local plain, on_dark = {}, {}
  for _, ref in ipairs(references) do
    local start = ref.range.start
    local is_dark = fg_at(bufnr, start.line, byte_col(bufnr, start, encoding)) == dark
    table.insert(is_dark and on_dark or plain, ref)
  end
  plain_highlight(bufnr, plain, encoding)
  for _, ref in ipairs(on_dark) do
    local s, e = ref.range.start, ref.range['end']
    vim.hl.range(bufnr, ns, kind_group[ref.kind or vim.lsp.protocol.DocumentHighlightKind.Text],
      { s.line, byte_col(bufnr, s, encoding) }, { e.line, byte_col(bufnr, e, encoding) },
      { priority = vim.hl.priorities.user })
  end
end
