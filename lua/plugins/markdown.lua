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
  preview = {
    icon_provider = 'devicons',                   -- real language icons (TS, etc.) instead of the internal blanks
    hybrid_modes = hybrid_mode and { 'n' } or {}, -- raw cursor line in normal mode (see flag above)
    linewise_hybrid_mode = true,                  -- de-render the whole cursor line, not just the element under it
  },
})
