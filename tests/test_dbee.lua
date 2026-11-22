-- nvim-dbee as plugins/dbee.lua sets it up: the project's DATABASE_URL from
-- .env is its connection, and queries run by the real backend open floats.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local BIN = vim.fn.stdpath('data') .. '/dbee/bin'

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nui.nvim', 'nvim-dbee', 'vim-dotenv' } })
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

return T
