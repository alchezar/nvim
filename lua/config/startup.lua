-- Startup layout: the file tree on the left and the shared right panel, so a fresh
-- session already looks like the one <leader>e / <leader>O would build by hand.

-- Flip to false to start with a bare window again.
local auto_open = true

-- Throwaway sessions keep the plain window: a commit editor, `nvim -d`, a headless run.
local one_shot = { gitcommit = true, gitrebase = true }

local function wants_layout()
  if not auto_open or vim.o.diff or #vim.api.nvim_list_uis() == 0 then return false end
  return not one_shot[vim.bo.filetype]
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    if not wants_layout() then return end
    -- Deferred: startify draws on its own VimEnter and re-centers around the splits,
    -- so the tree and the panel have to exist after that first render, not during it.
    vim.schedule(function()
      local api = require('nvim-tree.api')
      -- `nvim <dir>` already opened it; toggling then would close it.
      if not api.tree.is_visible() then api.tree.toggle({ focus = false }) end
      require('custom.side_panel').open()
    end)
  end,
})
