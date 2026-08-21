-- Telescope LSP pickers with a custom entry_maker that splits rows into
-- [code | file:line:col | mirrored path] so theme highlights can color each segment.

local utils = require('config.utils')
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
    local text = (item.text or ''):gsub('^%s+', '')
    -- The code line leads and the mirrored `file:line:col\parents` trails, so the
    -- meaningful text comes first and only the path root gets cut off.
    local loc, loc_style = utils.mirror_path(item.filename, {
      suffix  = ':' .. item.lnum .. ':' .. item.col,
      name_hl = 'TelescopeResultsFileName',
    })

    -- Classify once here; `display` may re-run on every redraw/scroll.
    local kind = opts.mark
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
        local prefix, pre_hl = '', nil
        if opts.mark then
          local mark = MARK[kind]
          prefix = mark and (mark[1] .. ' ') or '  ' -- align unmarked rows
          if mark then pre_hl = { { 0, #mark[1] }, mark[2] } end
        end
        local loc_at = #prefix + #text + #SEP
        local hls = { { { #prefix, #prefix + #text }, 'TelescopeResultsNormal' } }
        for _, st in ipairs(loc_style) do
          hls[#hls + 1] = { { loc_at + st[1][1], loc_at + st[1][2] }, st[2] }
        end
        if pre_hl then table.insert(hls, 1, pre_hl) end
        return prefix .. text .. SEP .. loc, hls
      end,
    }
  end
end

local kind_highlights = require('config.lsp_icons').symbol_highlights()
local actions = require('telescope.actions')

require('telescope').setup({
  defaults = {
    initial_mode = 'normal',
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
    live_grep                     = { initial_mode = 'insert' },
    -- Mirrored path wherever the row ends with one; live_grep keeps the plain
    -- leading `path:line:col:` since there the path is not the trailing column.
    find_files                    = { path_display = utils.mirror_path_display },
    oldfiles                      = { path_display = utils.mirror_path_display },
    -- `dd` in normal mode closes the buffer under the cursor without leaving the picker.
    buffers                       = { mappings = { n = { dd = actions.delete_buffer } } },
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
