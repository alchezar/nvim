-- markview: heading colors + code (block & inline) background mapped to kinder_theme palette

local theme = require('config.theme_colors')
local colors = { theme.red, theme.orange, theme.yellow, theme.green, theme.blue, theme.purple }

-- true: raw (unformatted) line under the cursor; false: full rendering everywhere.
local hybrid_mode = false

local function apply_markview_hl()
  for i, c in ipairs(colors) do
    vim.api.nvim_set_hl(0, 'KinderMarkdownH' .. i, { fg = c, bold = true })
  end
  -- Code blocks: darker than the editor background (bg #262626 -> black #181818).
  -- Block bg only (treesitter colors the code); inline code also forces gray text
  -- so it never inherits the surrounding red (e.g. inside an H1 heading).
  vim.api.nvim_set_hl(0, 'KinderMarkdownCode', { bg = theme.black })
  vim.api.nvim_set_hl(0, 'KinderMarkdownInlineCode', { bg = theme.black, fg = theme.gray })
  -- Horizontal rule: one muted full-width line, no center glyph or gradient.
  vim.api.nvim_set_hl(0, 'KinderMarkdownRule', { fg = theme.silver })
  -- Bold (**...**): teal, still bold. Scoped to markdown_inline so other langs keep theirs.
  vim.api.nvim_set_hl(0, '@markup.strong.markdown_inline', { fg = theme.teal, bold = true })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_markview_hl })
apply_markview_hl()

-- A rendered table only holds together at leftcol 0 without 'wrap': soft-wrap splits rows
-- mid-cell, a sideways scroll drifts the border. Show raw markdown rather than half-broken.
local function render_table(buffer, item)
  local win = require('markview.utils').buf_getwin(buffer)

  if type(win) ~= 'number' then
    return require('markview.renderers.markdown').table(buffer, item)
  end

  local leftcol = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview().leftcol end)

  if vim.wo[win].wrap or leftcol > 0 then return end

  return require('markview.renderers.markdown').table(buffer, item)
end

require('markview').setup({
  markdown = {
    headings = {
      enable = true,
      -- sign = false on H1/H2: their default signcolumn glyph would hide the bookmark icon.
      heading_1 = { style = 'icon', sign = false, hl = 'KinderMarkdownH1' },
      heading_2 = { style = 'icon', sign = false, hl = 'KinderMarkdownH2' },
      heading_3 = { style = 'icon', hl = 'KinderMarkdownH3' },
      heading_4 = { style = 'icon', hl = 'KinderMarkdownH4' },
      heading_5 = { style = 'icon', hl = 'KinderMarkdownH5' },
      heading_6 = { style = 'icon', hl = 'KinderMarkdownH6' },
    },
    code_blocks = {
      enable = true,
      style = 'block',
      border_hl = 'KinderMarkdownCode', -- top/bottom border rows
      info_hl = 'KinderMarkdownCode',   -- language label row
      label_hl = 'KinderMarkdownCode',  -- background behind the language name
      default = { block_hl = 'KinderMarkdownCode', pad_hl = 'KinderMarkdownCode' },
    },
    horizontal_rules = {
      enable = true,
      parts = {
        {
          type = 'repeating',
          direction = 'left',
          text = '─',
          hl = 'KinderMarkdownRule',
          repeat_amount = function(buffer)
            local win = require('markview.utils').buf_getwin(buffer)
            local width = vim.api.nvim_win_get_width(win)
            local textoff = vim.fn.getwininfo(win)[1].textoff
            return math.max(0, width - textoff)
          end,
        },
      },
    },
  },
  markdown_inline = {
    inline_codes = { enable = true, hl = 'KinderMarkdownInlineCode' },
  },
  renderers = {
    markdown_table = render_table,
  },
  preview = {
    icon_provider = 'devicons',                   -- real language icons (TS, etc.) instead of the internal blanks
    hybrid_modes = hybrid_mode and { 'n' } or {}, -- raw cursor line in normal mode (see flag above)
    linewise_hybrid_mode = true,                  -- de-render the whole cursor line, not just the element under it
  },
})

local pad_ns = vim.api.nvim_create_namespace('kinder_markdown_pad')
-- No code_span_delimiter: markview already pads inline code back to its raw width.
local pad_query = '(emphasis_delimiter) @full (backslash_escape) @first'

-- Hidden markup shortens a row, knocking table columns out of line. Conceal it to a
-- space instead: same width, still invisible. Needs 'conceallevel' 2; 3 drops the
-- replacement. Only table rows need it - elsewhere the padding is a visible gap.
local function pad_concealed(buffer, raw)
  vim.api.nvim_buf_clear_namespace(buffer, pad_ns, 0, -1)

  local ok, parser = pcall(vim.treesitter.get_parser, buffer, 'markdown')
  if not raw or not ok or not parser then return end

  local query = vim.treesitter.query.parse('markdown_inline', pad_query)

  parser:parse(true)
  parser:for_each_tree(function(tree, ltree)
    if ltree:lang() ~= 'markdown_inline' then return end

    for id, node in query:iter_captures(tree:root(), buffer) do
      local row, col, end_row, end_col = node:range()
      -- backslash_escape hides only its leading `\`, the escaped char stays visible.
      if query.captures[id] == 'first' then end_col = col + 1 end

      local line = vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or ''
      if row == end_row and line:match('^%s*|') then
        -- Per char: one extmark conceals its whole range to a single space.
        for c = col, end_col - 1 do
          vim.api.nvim_buf_set_extmark(buffer, pad_ns, row, c, {
            end_col = c + 1, conceal = ' ', priority = 5000, -- over the 4096 default
          })
        end
      end
    end
  end)
end

-- Prose wraps at word boundaries, not mid-word, once <M-z> turns 'wrap' on;
-- breakindent keeps continuation rows under the list item they belong to.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
  end,
})

-- Flip the window between rendered and raw. Needed because markview only repaints on
-- cursor moves in hybrid mode, so 'wrap'/leftcol changes go unnoticed.
local function sync_raw(win, buffer)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buffer then return end

  local leftcol = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview().leftcol end)
  local raw = vim.wo[win].wrap or leftcol > 0

  if vim.w[win].markview_raw == raw then return end
  vim.w[win].markview_raw = raw

  vim.wo[win].conceallevel = raw and 2 or 3
  pad_concealed(buffer, raw)
  require('markview.actions').render(buffer)
end

vim.api.nvim_create_autocmd({ 'WinScrolled', 'OptionSet', 'BufWinEnter' }, {
  callback = function(args)
    if args.event == 'OptionSet' and args.match ~= 'wrap' then return end

    local win = args.event == 'WinScrolled' and tonumber(args.match) or vim.api.nvim_get_current_win()
    if not vim.api.nvim_win_is_valid(win) then return end
    -- Read the buffer off the window: OptionSet reports args.buf as 0, which never
    -- matches the window's real buffer and made sync_raw bail out on every toggle.
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype ~= 'markdown' then return end

    -- Deferred: markview sets conceallevel on attach, and rendering inside the scroll does nothing.
    vim.schedule(function() sync_raw(win, buf) end)
  end,
})
