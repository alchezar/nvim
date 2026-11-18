-- Startify dashboard layout from plugins/startify_setup.lua. Entries sit at the
-- same screen column with or without the tree, lined up under their title.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-web-devicons', 'vim-startify' } })
      child.o.lines, child.o.columns = 40, 220
      local a, b = vim.fn.tempname(), vim.fn.tempname()
      vim.fn.writefile({}, a)
      vim.fn.writefile({}, b)
      child.lua([[
        -- No private project list: the dashboard holds only these recent files.
        package.loaded['config.projects'] = {}
        vim.v.oldfiles = { ... }
        _G.ready_at = nil
        vim.api.nvim_create_autocmd('User', {
          pattern = 'StartifyReady',
          callback = function() _G.ready_at = vim.uv.hrtime() end,
        })
        -- Startify re-renders itself once it knows its width; wait for quiet.
        function _G.settle()
          vim.wait(3000, function()
            return _G.ready_at ~= nil and vim.uv.hrtime() - _G.ready_at > 2e8
          end, 20)
        end
        require('plugins.startify_setup')
      ]], { a, b })
    end,
    post_once = child.stop,
  },
})

-- Screen columns of the `[` of each entry and of the "Recent files" title.
local function layout()
  return child.lua([[
    _G.settle()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'startify' then
        local wincol = vim.api.nvim_win_get_position(w)[2]
        local entries, title = {}, nil
        for _, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
          if l:match('^%s*%[') then entries[#entries + 1] = wincol + l:find('[', 1, true) end
          local t = l:find('Recent files', 1, true)
          if t then title = wincol + t end
        end
        return { entries = entries, title = title }
      end
    end
  ]])
end

local function open_dashboard()
  child.cmd('doautocmd VimEnter')
end

-- Before 5ba3187 the padding came from the dashboard's own width, and until
-- 4f40346 startify's frozen padding ignored it, so the tree beside the
-- dashboard pushed the entries right.
T['entries stay put when the tree opens beside'] = function()
  open_dashboard()
  local alone = layout()
  child.cmd('topleft 30vnew | setlocal filetype=NvimTree | wincmd l')
  local beside = layout()
  eq(beside.entries[1], alone.entries[1])
end

-- Before 4f40346, startify's frozen left padding ignored the centering, so
-- entries and their section title drifted apart.
T['entries line up under their title'] = function()
  open_dashboard()
  local l = layout()
  eq(#l.entries >= 2, true)
  for _, col in ipairs(l.entries) do eq(col, l.title - 3) end
end

return T
