-- Numbered bookmarks via `chentoast/marks.nvim`
--   m[0-9]    toggle bookmark at cursor in group N
--   `[0-9]    jump to next bookmark in group N (cyclic)
--   dm[0-9]   delete entire group N (whole buffer)
--   <M-m>     delete any mark/bookmark on current line
--   <leader>m list all numbered bookmarks
--   <leader>M list all letter marks

local theme = require('theme_colors')

-- Sign column highlight for marks/bookmarks - yellow instead of default gray.
-- Only the sign glyph is colored; the line number keeps its default color.
vim.api.nvim_set_hl(0, 'MarkSignHL', { fg = theme.yellow })

require('marks').setup({
  default_mappings = true,
  signs = true,
  cyclic = true,
  force_write_shada = false,
  bookmark_0 = { sign = '0' },
  bookmark_1 = { sign = '1' },
  bookmark_2 = { sign = '2' },
  bookmark_3 = { sign = '3' },
  bookmark_4 = { sign = '4' },
  bookmark_5 = { sign = '5' },
  bookmark_6 = { sign = '6' },
  bookmark_7 = { sign = '7' },
  bookmark_8 = { sign = '8' },
  bookmark_9 = { sign = '9' },
})

for i = 0, 9 do
  vim.keymap.set('n', 'm' .. i, function()
    require('marks')['toggle_bookmark' .. i]()
  end, { desc = 'Toggle bookmark ' .. i })
  vim.keymap.set('n', '`' .. i, function()
    require('marks')['next_bookmark' .. i]()
  end, { desc = 'Jump to bookmark ' .. i })
end

vim.keymap.set('n', '<M-m>', function()
  local marks = require('marks')
  marks.delete_bookmark()  -- numbered bookmark groups (0-9)
  marks.delete_line()      -- letter marks (a-z, A-Z)
end, { desc = 'Delete any mark/bookmark on current line' })

-- marks.nvim populates the *location list* (not quickfix) and auto-opens it.
-- Close the loclist window, then surface the entries via telescope.loclist so
-- the entry_maker in lua/telescope_setup.lua colors path / line:col / text.
local function in_telescope(populate_cmd, title)
  return function()
    vim.cmd(populate_cmd)
    pcall(vim.cmd, 'lclose')
    require('telescope.builtin').loclist({ prompt_title = title })
  end
end

vim.keymap.set('n', '<leader>m', in_telescope('BookmarksListAll', 'Bookmarks (0-9)'),
  { desc = 'List all numbered bookmarks (Telescope)', silent = true })
vim.keymap.set('n', '<leader>M', in_telescope('MarksListAll', 'Marks (a-z, A-Z)'),
  { desc = 'List all letter marks (Telescope)', silent = true })
