-- nvim-dbee as plugins/dbee.lua sets it up: the project's DATABASE_URL from
-- .env is its connection, and queries run by the real backend open floats.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local BIN = vim.fn.stdpath('data') .. '/dbee/bin'

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nui.nvim', 'nvim-dbee', 'vim-dotenv', 'nvim-cmp' } })
      child.o.lines, child.o.columns = 40, 160
      -- The child keeps its own data dir; lend it the installed backend.
      child.lua([[
        local dir = vim.fn.stdpath('data') .. '/dbee'
        vim.fn.mkdir(dir, 'p')
        vim.uv.fs_symlink(..., dir .. '/bin')
      ]], { BIN })
    end,
    post_once = child.stop,
  },
})

-- A project dir whose .env holds `url`.
local function project(url)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  dir = assert(vim.uv.fs_realpath(dir))
  vim.fn.writefile({ 'DATABASE_URL=' .. url }, dir .. '/.env')
  return dir
end

T['the project url gets decoded and postgres skips ssl unless told'] = function()
  child.lua('vim.cmd.cd(...)', { project('postgres://me:p%40ss@localhost/app') })
  child.lua([[require('plugins.dbee')]])
  local first = child.g.dbee_project_url
  child.lua('vim.cmd.cd(...)', { project('postgres://me@db/app?sslmode=require') })
  eq({ first, child.g.dbee_project_url },
    { 'postgres://me:p@ss@localhost/app?sslmode=disable', 'postgres://me@db/app?sslmode=require' })
end

-- 96de77c stopped binding the call log at open, which made dbee show it on
-- every new call. Today's nvim and dbee keep it hidden either way, so this
-- only guards it.
T['a query shows its result, not the call log'] = function()
  if vim.fn.executable(BIN .. '/dbee') == 0 then MiniTest.skip('dbee backend is not installed') end
  local dir = project('sqlite://' .. vim.fn.tempname() .. '.db')
  child.lua('vim.cmd.cd(...)', { dir })
  local got = child.lua([[
    require('plugins.dbee')
    local dbee = require('dbee')
    dbee.open()
    vim.wait(3000, function() return dbee.api.core.is_loaded() end)
    local conns = dbee.api.core.source_get_connections('project')
    dbee.api.core.set_current_connection('project_env')
    dbee.execute('SELECT 1')
    local function shown()
      local out = {}
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative ~= '' and not c.hide then out[#out + 1] = vim.trim(c.title[1][1]) end
      end
      table.sort(out)
      return out
    end
    vim.wait(3000, function() return #shown() > 0 end)
    -- A late call log would show up after the result.
    vim.wait(500)
    return { type = conns[1] and conns[1].type, shown = shown() }
  ]])
  eq(got, { type = 'sqlite', shown = { 'Query result (q / <Esc> to hide)' } })
end

-- dbee open on a fresh sqlite project, its connection current.
local function open_ui()
  if vim.fn.executable(BIN .. '/dbee') == 0 then MiniTest.skip('dbee backend is not installed') end
  child.lua('vim.cmd.cd(...)', { project('sqlite://' .. vim.fn.tempname() .. '.db') })
  child.lua([[
    require('plugins.dbee')
    local dbee = require('dbee')
    dbee.open()
    vim.wait(3000, function() return dbee.api.core.is_loaded() end)
    dbee.api.core.source_get_connections('project')
    dbee.api.core.set_current_connection('project_env')
  ]])
end

-- Titles of the editor floats on screen and the title of the focused one, ''
-- for a plain window. dbee's own call detail popup sits on a window, not the
-- editor, and is left out.
local function floats()
  return child.lua([[
    local function title(w)
      local c = vim.api.nvim_win_get_config(w)
      if c.relative == '' then return '' end
      return c.title and vim.trim(c.title[1][1]):match('^[%w ]+%f[ ]') or '?'
    end
    local shown = {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local c = vim.api.nvim_win_get_config(w)
      if c.relative == 'editor' and not c.hide then shown[#shown + 1] = title(w) end
    end
    table.sort(shown)
    return { shown = shown, focus = title(vim.api.nvim_get_current_win()) }
  ]])
end

T['a float opens focused and q or esc hides it, focus going back'] = function()
  open_ui()
  local mod = 'require("plugins.dbee")'
  child.lua(mod .. '.show_editor()')
  local editor = floats()
  child.type_keys('<Esc>')
  local after_esc = floats()
  child.lua(mod .. '.show_call_log()')
  local log = floats()
  child.type_keys('q')
  eq({ editor, after_esc, log, floats() }, {
    { shown = { 'SQL editor' }, focus = 'SQL editor' },
    { shown = {},               focus = '' },
    { shown = { 'Call log' },   focus = 'Call log' },
    { shown = {},               focus = '' },
  })
end

T['running the line under the cursor in the editor shows its result'] = function()
  open_ui()
  child.lua([[
    require('plugins.dbee').show_editor()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'SELECT 1;' })
    require('config.utils').dbee_run()
    vim.wait(3000, function()
      local c = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
      return c.relative ~= '' and c.title[1][1]:find('Query result') ~= nil
    end)
  ]])
  eq(floats(), { shown = { 'Query result', 'SQL editor' }, focus = 'Query result' })
end

T['running with no connection only warns'] = function()
  child.lua('vim.cmd.cd(...)', { vim.fn.tempname():match('.*/') })
  child.lua([[
    _G.notes = {}
    vim.notify = function(msg) table.insert(_G.notes, msg) end
    require('plugins.dbee')
    require('config.utils').dbee_run()
  ]])
  eq(child.lua_get('_G.notes[1]'):match('^Dbee: no active connection') ~= nil, true)
end

-- Before 7be0953, closing skipped the drawer while the lazy call log window
-- was never opened.
T[':DBUIOpen opens the drawer and closes it again'] = function()
  if vim.fn.executable(BIN .. '/dbee') == 0 then MiniTest.skip('dbee backend is not installed') end
  child.lua('vim.cmd.cd(...)', { project('sqlite://' .. vim.fn.tempname() .. '.db') })
  child.lua([[require('plugins.dbee')]])
  local function drawer()
    return child.lua_get([[require('plugins.dbee').layout:is_open()]])
  end
  child.cmd('DBUIOpen')
  local opened = drawer()
  child.cmd('DBUIOpen')
  eq({ opened, drawer(), #child.api.nvim_list_wins() }, { true, false, 1 })
end

return T
