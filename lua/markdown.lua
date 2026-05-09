-- render-markdown: heading colors mapped to kinder_theme palette

local theme = require('theme_colors')
local levels = { 'H1', 'H2', 'H3', 'H4', 'H5', 'H6' }
local colors = { theme.red, theme.orange, theme.yellow, theme.green, theme.blue, theme.purple }

local function apply_heading_hl()
  for i, lvl in ipairs(levels) do
    vim.api.nvim_set_hl(0, 'RenderMarkdownH' .. i,    { fg = colors[i], bold = true })
    vim.api.nvim_set_hl(0, 'RenderMarkdownH' .. i .. 'Bg', {})
  end
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_heading_hl })
apply_heading_hl()

require('render-markdown').setup({
  heading = {
    foregrounds = {
      'RenderMarkdownH1',
      'RenderMarkdownH2',
      'RenderMarkdownH3',
      'RenderMarkdownH4',
      'RenderMarkdownH5',
      'RenderMarkdownH6',
    },
    backgrounds = {},
  },
})
