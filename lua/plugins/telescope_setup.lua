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

-- Read/write usage markers (RustRover-style green/red access arrows).
local theme = require('config.theme_colors')
vim.api.nvim_set_hl(0, 'TelescopeUsageRead', { fg = theme.green })
vim.api.nvim_set_hl(0, 'TelescopeUsageWrite', { fg = theme.red })
local MARK = {
  read  = { '↑', 'TelescopeUsageRead' },
  write = { '↓', 'TelescopeUsageWrite' },
}

-- `mark` adds an access-kind arrow column; used by lsp_references only.
local function lsp_entry_maker(opts)
  opts = opts or {}
  return function(item)
    if not item or not item.filename then return nil end
    local path     = relpath(item.filename)
    local line_col = item.lnum .. ':' .. item.col
    local text     = (item.text or ''):gsub('^%s+', '')
    local line     = path .. SEP .. line_col .. SEP .. text
    local p1       = #path
    local p2       = p1 + #SEP + #line_col
    local p3       = p2 + #SEP + #text
    -- Classify once here; `display` may re-run on every redraw/scroll.
    local kind     = opts.mark
        and require('config.usage_kind').classify(item.filename, item.lnum, item.col)
        or nil
    return {
      value    = item,
      ordinal  = item.filename .. ' ' .. text,
      filename = item.filename,
      lnum     = item.lnum,
      col      = item.col,
      text     = text,
      display  = function()
        if not opts.mark then
          return line, {
            { { 0, p1 },         'TelescopeResultsFileName' },
            { { p1 + #SEP, p2 }, 'TelescopeResultsLineNr' },
            { { p2 + #SEP, p3 }, 'TelescopeResultsNormal' },
          }
        end
        local mark = MARK[kind]
        local prefix = mark and (mark[1] .. ' ') or '  ' -- align unmarked rows
        local off = #prefix
        local hls = {
          { { off, off + p1 },             'TelescopeResultsFileName' },
          { { off + p1 + #SEP, off + p2 }, 'TelescopeResultsLineNr' },
          { { off + p2 + #SEP, off + p3 }, 'TelescopeResultsNormal' },
        }
        if mark then table.insert(hls, 1, { { 0, #mark[1] }, mark[2] }) end
        return prefix .. line, hls
      end,
    }
  end
end

local kind_highlights = require('config.lsp_icons').symbol_highlights()

require('telescope').setup({
  defaults = {
    path_display = { 'truncate' },
    -- Prompt on top with preview to the side; `ascending` keeps the best match
    -- right under the prompt instead of at the bottom of the list.
    sorting_strategy = 'ascending',
    layout_strategy = 'horizontal',
    layout_config = {
      prompt_position = 'top',
      preview_width = 80,
    },
  },
  pickers = {
    lsp_references                = { entry_maker = lsp_entry_maker({ mark = true }) },
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
