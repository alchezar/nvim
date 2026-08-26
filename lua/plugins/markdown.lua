-- markview: heading colors + code (block & inline) background mapped to kinder_theme palette

local theme = require('config.theme_colors')
local colors = { theme.red, theme.orange, theme.yellow, theme.green, theme.blue, theme.purple }

-- true: raw (unformatted) line under the cursor; false: full rendering everywhere.
local hybrid_mode = false

local function apply_markview_hl()
  for i, c in ipairs(colors) do
    vim.api.nvim_set_hl(0, 'KinderMarkdownH' .. i, { fg = c, bold = true })
  end
  -- Code blocks: darker than the editor background, shaded per UI (utils.shade).
  -- Block bg only (treesitter colors the code); inline code also forces gray text
  -- so it never inherits the surrounding red (e.g. inside an H1 heading).
  local utils = require('config.utils')
  vim.api.nvim_set_hl(0, 'KinderMarkdownCode', utils.shade())
  vim.api.nvim_set_hl(0, 'KinderMarkdownInlineCode', utils.shade({ fg = theme.gray }))
  -- Horizontal rule: one muted full-width line, no center glyph or gradient.
  vim.api.nvim_set_hl(0, 'KinderMarkdownRule', { fg = theme.silver })
  -- Bold (**...**): teal, still bold. Scoped to markdown_inline so other langs keep theirs.
  vim.api.nvim_set_hl(0, '@markup.strong.markdown_inline', { fg = theme.teal, bold = true })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_markview_hl })
apply_markview_hl()

-- markview's own table render only holds together at leftcol 0 without 'wrap'.
-- Under 'wrap' draw our own word-wrapped table; a sideways scroll still degrades
-- to raw markdown (the box would drift with leftcol).
local function render_table(buffer, item)
  local win = require('markview.utils').buf_getwin(buffer)

  if type(win) ~= 'number' then
    return require('markview.renderers.markdown').table(buffer, item)
  end

  local leftcol = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview().leftcol end)

  if vim.wo[win].wrap then return require('custom.markdown_table_wrap').render(buffer, item, win) end
  -- Back to nowrap: drop our marks or they would sit over markview's own render.
  require('custom.markdown_table_wrap').clear(buffer, item)
  if leftcol > 0 then return end

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
      org_indent_wrap = false, -- same heuristic wrap indent as list_items below
    },
    code_blocks = {
      enable = true,
      -- 'block' pads every line out to the widest one with inline virt_text; under
      -- 'wrap' that padding soft-wraps and shreds the background into stray rows.
      style = function(buffer)
        local win = require('markview.utils').buf_getwin(buffer)
        if type(win) == 'number' and vim.wo[win].wrap then return 'simple' end
        return 'block'
      end,
      border_hl = 'KinderMarkdownCode', -- top/bottom border rows
      info_hl = 'KinderMarkdownCode',   -- language label row
      label_hl = 'KinderMarkdownCode',  -- background behind the language name
      default = { block_hl = 'KinderMarkdownCode', pad_hl = 'KinderMarkdownCode' },
    },
    -- markview guesses the wrap point as text_width/win_width, which lands mid-word
    -- under 'linebreak'. 'breakindentopt' below indents wrapped rows instead.
    -- add_padding puts the item's indent in virtual columns 'breakindent' can't count,
    -- so keeping it would need a global shift that also indents plain paragraphs.
    list_items = {
      enable = true,
      wrap = false,
      marker_minus = { add_padding = false },
      marker_plus = { add_padding = false },
      marker_star = { add_padding = false },
      marker_dot = { add_padding = false },
      marker_parenthesis = { add_padding = false },
    },
    block_quotes = { enable = true, wrap = false },
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

-- markview de-renders on insert by clearing only its own namespaces, so our
-- wrapped table would stay; piggyback its markdown clear to drop ours too.
local md_renderer = require('markview.renderers.markdown')
local md_clear = md_renderer.clear
md_renderer.clear = function(buffer, from, to, hybrid)
  require('custom.markdown_table_wrap').clear_range(buffer, from or 0, to or -1)
  return md_clear(buffer, from, to, hybrid)
end

-- Under 'wrap' our own box covers the table's source rows, but markview's inline
-- pass still pads and conceals inside them, which moves the soft-wrap points the
-- box is anchored on. Drop inline items sitting on a table row.
local inline_renderer = require('markview.renderers.markdown_inline')
local inline_render = inline_renderer.render
inline_renderer.render = function(buffer, content, heading_lines)
  local win = require('markview.utils').buf_getwin(buffer)
  if type(win) == 'number' and vim.wo[win].wrap then
    local cache, kept = {}, {}
    for _, item in ipairs(content or {}) do
      local row = item.range and item.range.row_start
      if row and cache[row] == nil then
        local line = vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or ''
        cache[row] = line:match('^%s*|') ~= nil
      end
      if not row or not cache[row] then kept[#kept + 1] = item end
    end
    content = kept
  end
  return inline_render(buffer, content, heading_lines)
end

local pad_ns = vim.api.nvim_create_namespace('kinder_markdown_pad')
-- No code_span_delimiter: markview already pads inline code back to its raw width.
local pad_query = '(emphasis_delimiter) @full (backslash_escape) @first'

-- A table scrolled sideways (leftcol > 0) shows raw, where hidden markup like '**'
-- shortens the row and drifts the '|' columns. Conceal it to spaces instead: same
-- width, still invisible. Needs 'conceallevel' 2; table rows only.
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

-- Wrap prose by word, continuation rows under the item's text. list:-1 needs
-- 'formatlistpat' to see markdown bullets; no shift, so paragraphs keep their own indent.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.breakindentopt = 'list:-1'
    vim.opt_local.formatlistpat = [[^\s*[-*+]\s\+\|^\s*\d\+[.)]\s\+\|^\s*\[[ x]\]\s\+]]
    vim.opt_local.formatoptions:remove('t')
  end,
})

-- Flip the window between rendered and raw. Needed because markview only repaints on
-- cursor moves in hybrid mode, so 'wrap'/leftcol changes go unnoticed.
local function sync_raw(win, buffer)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buffer then return end
  -- markview never attaches to 'nofile' buffers (LSP hover, previews). Rendering one
  -- here would repaint it on the first scroll, mid-view.
  if not require('markview.state').buf_attached(buffer) then return end

  local leftcol = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview().leftcol end)
  local raw = vim.wo[win].wrap or leftcol > 0

  -- Width matters too: the box is laid out for one exact text width and its overlays
  -- sit on byte columns derived from it, so a resize has to repaint.
  local width = vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
  if vim.w[win].markview_raw == raw and vim.w[win].markview_width == width then return end
  vim.w[win].markview_raw, vim.w[win].markview_width = raw, width

  vim.wo[win].conceallevel = raw and 2 or 3
  pad_concealed(buffer, raw)
  require('markview.actions').render(buffer)
end

vim.api.nvim_create_autocmd({ 'WinScrolled', 'WinResized', 'OptionSet', 'BufWinEnter' }, {
  callback = function(args)
    if args.event == 'OptionSet' and args.match ~= 'wrap' then return end

    -- WinResized names every affected window; the others carry just the one.
    local wins = args.event == 'WinResized' and vim.v.event.windows
        or { args.event == 'WinScrolled' and tonumber(args.match) or vim.api.nvim_get_current_win() }

    for _, win in ipairs(wins or {}) do
      if vim.api.nvim_win_is_valid(win) then
        -- OptionSet reports args.buf as 0, which never matches the window's real buffer.
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == 'markdown' then
          -- Deferred: markview sets conceallevel on attach, and rendering inside the scroll does nothing.
          vim.schedule(function() sync_raw(win, buf) end)
        end
      end
    end
  end,
})
