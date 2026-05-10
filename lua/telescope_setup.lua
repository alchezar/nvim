-- Telescope setup with custom entry maker for LSP pickers.
-- Splits each result row into [filename, line:col, code] segments so the theme
-- highlights (TelescopeResultsFileName / LineNr / Normal) can color them
-- independently. Default gen_from_quickfix concatenates everything into one
-- string, which is why the same highlight applied to the whole row.

-- Make the absolute filename relative to cwd; if outside cwd, use ~/-form.
local function relpath(filename)
  local cwd = vim.fn.getcwd()
  if filename:sub(1, #cwd + 1) == cwd .. '/' then
    return filename:sub(#cwd + 2)
  end
  return vim.fn.fnamemodify(filename, ':~')
end

local SEP = '  '  -- two spaces between segments

local function lsp_entry_maker(_)
  return function(item)
    if not item or not item.filename then return nil end
    local path     = relpath(item.filename)
    local line_col = item.lnum .. ':' .. item.col
    local text     = (item.text or ''):gsub('^%s+', '')  -- trim leading ws
    local line     = path .. SEP .. line_col .. SEP .. text
    -- Pre-compute byte offsets for highlight regions.
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

require('telescope').setup({
  defaults = {
    path_display = { 'truncate' },
  },
  pickers = {
    lsp_references      = { entry_maker = lsp_entry_maker() },
    lsp_implementations = { entry_maker = lsp_entry_maker() },
    lsp_definitions     = { entry_maker = lsp_entry_maker() },
    lsp_type_definitions= { entry_maker = lsp_entry_maker() },
  },
})
