-- The whole config starting for real, with init.lua and installed plugins.
-- State and cache go to a temp dir, so the real shada and undo stay intact.
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

local function start_config()
  local tmp = vim.fn.tempname()
  local report = tmp .. '/report.json'
  -- Startify warns on every start while oldfiles is empty, as in a fresh
  -- state. A real start always has some history, so give it one entry.
  local history = ('let v:oldfiles = [%s]'):format(vim.fn.string(vim.fn.getcwd() .. '/init.lua'))
  local cmd = { vim.v.progpath, '--headless', '--cmd', history, '-c', 'luafile tests/smoke_probe.lua' }
  local res = vim.system(cmd, {
    env = { XDG_STATE_HOME = tmp .. '/state', XDG_CACHE_HOME = tmp .. '/cache', SMOKE_REPORT = report },
    timeout = 30000,
  }):wait()
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(report), '\n')) end)
  return res, ok and data or nil
end

T['starts without output and every lua module loads'] = function()
  local res, report = start_config()
  -- Headless nvim exits 0 even after a startup error; it prints errors,
  -- notify() and print() to stderr, so an empty stderr is the real check.
  eq(res.stderr, '')
  eq(res.code, 0)
  if not report then error('probe wrote no report: startup hung or quit early') end
  -- Run from another checkout, nvim would load ~/.config/nvim, not that one.
  eq(vim.uv.fs_realpath(report.config), vim.uv.fs_realpath(vim.fn.getcwd()))
  eq(report.failed, {})
end

return T
