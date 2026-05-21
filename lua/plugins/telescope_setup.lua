-- Telescope LSP pickers with a custom entry_maker that splits rows into
-- [filename | line:col | code] so theme highlights can color each segment.

-- Path relative to cwd; outside cwd falls back to `~`-form.
local function relpath(filename)
  local cwd = vim.fn.getcwd()
  if filename:sub(1, #cwd + 1) == cwd .. '/' then
    return filename:sub(#cwd + 2)
  end
  return vim.fn.fnamemodify(filename, ':~')
end

local SEP = '  '

local function lsp_entry_maker(_)
  return function(item)
    if not item or not item.filename then return nil end
    local path     = relpath(item.filename)
    local line_col = item.lnum .. ':' .. item.col
    local text     = (item.text or ''):gsub('^%s+', '')
    local line     = path .. SEP .. line_col .. SEP .. text
    local p1 = #path
    local p2 = p1 + #SEP + #line_col
    local p3 = p2 + #SEP + #text
    return {
      value    = item,
      ordinal  = item.filename .. ' ' .. text,
      filename = item.filename,
      lnum     = item.lnum,
      col      = item.col,
      text     = text,
      display  = function()
        return line, {
          { { 0,             p1 }, 'TelescopeResultsFileName' },
          { { p1 + #SEP,     p2 }, 'TelescopeResultsLineNr'   },
          { { p2 + #SEP,     p3 }, 'TelescopeResultsNormal'   },
        }
      end,
    }
  end
end

local kind_highlights = require('config.lsp_icons').symbol_highlights()

require('telescope').setup({
  defaults = {
    path_display = { 'truncate' },
  },
  pickers = {
    lsp_references                = { entry_maker = lsp_entry_maker() },
    lsp_implementations           = { entry_maker = lsp_entry_maker() },
    lsp_definitions               = { entry_maker = lsp_entry_maker() },
    lsp_type_definitions          = { entry_maker = lsp_entry_maker() },
    quickfix                      = { entry_maker = lsp_entry_maker() },
    loclist                       = { entry_maker = lsp_entry_maker() },
    lsp_document_symbols          = { symbol_highlights = kind_highlights },
    lsp_workspace_symbols         = { symbol_highlights = kind_highlights },
    lsp_dynamic_workspace_symbols = { symbol_highlights = kind_highlights },
  },
})
