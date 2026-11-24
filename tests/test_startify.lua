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

-- Before f8c667e, startify's window-local EndOfBuffer map, which hides '~'
-- when Normal has a bg, was copied into every split off the dashboard.
T['a split off the dashboard keeps the eob markers'] = function()
  child.lua([[
    vim.o.termguicolors = true
    vim.api.nvim_set_hl(0, 'Normal', { bg = '#101010' })
  ]])
  open_dashboard()
  child.lua([[_G.settle()]])
  child.cmd('vsplit')
  eq(child.lua_get([[vim.wo.winhighlight:find('StartifyEndOfBuffer') == nil]]), true)
end

-- Before 4f40346, startify's frozen left padding ignored the centering, so
-- entries and their section title drifted apart.
T['entries line up under their title'] = function()
  open_dashboard()
  local l = layout()
  eq(#l.entries >= 2, true)
  for _, col in ipairs(l.entries) do eq(col, l.title - 3) end
end

T['a project group is its own section and its entry cds there'] = function()
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  vim.fn.mkdir(dir, 'p')
  child.lua([[
    package.loaded['config.projects'] = { _order = { 'Work' }, Work = { { path = ..., name = 'shop', icon = 'W' } } }
  ]], { dir })
  open_dashboard()
  child.lua('_G.settle()')
  local lines = vim.tbl_map(vim.trim, child.api.nvim_buf_get_lines(0, 0, -1, false))
  local at = vim.fn.index(lines, 'Work')
  local section = { lines[at + 1], lines[at + 3] }
  child.api.nvim_win_set_cursor(0, { at + 3, 0 })
  -- Startify opens it under `silent!` with a stray E490 left in v:errmsg,
  -- which type_keys would take for a failure.
  child.cmd([[execute "normal \<CR>"]])
  eq({ section, child.fn.getcwd() }, { { 'Work', '[0]  W  shop' }, dir })
end

-- The pool is random, so the copy is checked against the balloon on screen.
T['y copies the quote or tip on show as one line'] = function()
  open_dashboard()
  child.lua('_G.settle()')
  local balloon = {}
  for _, l in ipairs(child.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local text = l:match('│ (.-)%s*│')
    if text then balloon[#balloon + 1] = text end
  end
  child.type_keys('y')
  local copied = child.fn.getreg('"')
  local function words(t) return (t:gsub('%s+->%s+', ' '):gsub('%s+', ' ')) end
  eq({ copied:find('\n') == nil, words(copied) }, { true, words(table.concat(balloon, ' ')) })
end

return T
