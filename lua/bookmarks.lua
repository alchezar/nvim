-- Numbered bookmarks via `chentoast/marks.nvim`
--   m[0-9]    toggle bookmark at cursor in group N
--   `[0-9]    jump to next bookmark in group N (cyclic)
--   dm[0-9]   delete entire group N (whole buffer)
--   <M-m>     delete any mark/bookmark on current line
--   <leader>m list all numbered bookmarks
--   <leader>M list all letter marks

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

vim.keymap.set('n', '<leader>m', ':BookmarksListAll<CR>',
  { desc = 'List all numbered bookmarks (0-9)', silent = true })
vim.keymap.set('n', '<leader>M', ':MarksListAll<CR>',
  { desc = 'List all letter marks (a-z, A-Z)', silent = true })
