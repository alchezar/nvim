-- Server choices from plugins/lsp.lua: where eslint and basedpyright root,
-- which python and lua runtime they get, and the diagnostic pull on entry.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-cmp', 'cmp-nvim-lsp', 'nvim-lspconfig' } })
      child.lua([[require('plugins.lsp')]])
    end,
    post_once = child.stop,
  },
})

-- A dir holding `files` (path -> lines, or true for an executable script).
local function tree(files)
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  for path, body in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(dir .. '/' .. path), 'p')
    vim.fn.writefile(body == true and { '#!/bin/sh' } or body, dir .. '/' .. path)
    if body == true then vim.uv.fs_chmod(dir .. '/' .. path, 493) end
  end
  return dir
end

-- Root `server` picks for `file`, false when it stays off. The buffer is
-- named, not read, so no filetype starts a real server.
local function root(server, file)
  return child.lua([[
    local server, file = ...
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, file)
    local got = false
    vim.lsp.config[server].root_dir(buf, function(dir) got = dir end)
    return got
  ]], { server, file })
end

T['eslint attaches only where a config file is'] = function()
  local dir = tree({ ['app/eslint.config.mjs'] = {}, ['app/src/a.ts'] = {}, ['bare/b.ts'] = {} })
  eq({ root('eslint', dir .. '/app/src/a.ts'), root('eslint', dir .. '/bare/b.ts') }, { dir .. '/app', false })
end

T['a python file roots at its project, not an outer git repo'] = function()
  local dir = tree({ ['.git/HEAD'] = {}, ['svc/pyproject.toml'] = {}, ['svc/m/a.py'] = {}, ['tool.py'] = {} })
  eq({ root('basedpyright', dir .. '/svc/m/a.py'), root('basedpyright', dir .. '/tool.py') }, { dir .. '/svc', dir })
end

-- pythonPath basedpyright starts with for a workspace at `dir`.
local function python(dir, venv)
  return child.lua([[
    local dir, venv = ...
    vim.env.VIRTUAL_ENV = venv
    local config = { settings = { python = {} } }
    vim.lsp.config.basedpyright.before_init({ workspaceFolders = { { uri = vim.uri_from_fname(dir) } } }, config)
    return config.settings.python.pythonPath or false
  ]], { dir, venv or vim.NIL })
end

T['python runs from the project venv, an active one first'] = function()
  local dir = tree({ ['.venv/bin/python'] = true, ['other/bin/python'] = true })
  local bare = tree({ ['x.py'] = {} })
  eq({ python(dir), python(dir, dir .. '/other'), python(bare) },
    { dir .. '/.venv/bin/python', dir .. '/other/bin/python', false })
end

-- Lua settings lua_ls ends up with in a workspace at `dir`.
local function lua_settings(dir)
  return child.lua([[
    local client = {
      workspace_folders = { { name = ... } },
      config = { settings = vim.deepcopy(vim.lsp.config.lua_ls.settings) },
    }
    vim.lsp.config.lua_ls.on_init(client)
    local lua = client.config.settings.Lua
    return { runtime = lua.runtime and lua.runtime.version or false, library = lua.workspace ~= nil }
  ]], { dir })
end

T['lua_ls leaves a project .luarc.json alone, else knows nvim'] = function()
  eq({ lua_settings(tree({ ['.luarc.json'] = { '{}' } })), lua_settings(tree({ ['a.lua'] = {} })) },
    { { runtime = false, library = false }, { runtime = 'LuaJIT', library = true } })
end

-- A rust buffer whose server answers diagnostic pulls with `message`.
local function pulled(message)
  return {
    kind = 'full',
    items = { {
      message = message,
      severity = 1,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 } }
    } }
  }
end

local function messages()
  return child.lua([[
    vim.wait(1000, function() return #vim.diagnostic.get(0) > 0 end)
    return vim.tbl_map(function(d) return d.message end, vim.diagnostic.get(0))
  ]])
end

T['entering a buffer pulls its diagnostics again'] = function()
  local dir = tree({ ['a.rs'] = { 'fn a() {}' }, ['b.rs'] = { 'fn b() {}' } })
  child.cmd('edit ' .. dir .. '/a.rs')
  H.start_fake_lsp(child, { ['textDocument/diagnostic'] = pulled('old') }, { diagnosticProvider = {} })
  child.cmd('edit ' .. dir .. '/b.rs')
  child.cmd('edit ' .. dir .. '/a.rs')
  local first = messages()
  child.lua([[_G.fake_lsp_responses['textDocument/diagnostic'] = ...]], { pulled('new') })
  child.cmd('edit ' .. dir .. '/b.rs')
  child.cmd('edit ' .. dir .. '/a.rs')
  child.lua([[vim.wait(1000, function() return vim.diagnostic.get(0)[1].message == 'new' end)]])
  eq({ first, messages() }, { { 'old' }, { 'new' } })
end

T['a pull refresh gone from nvim is reported, once'] = function()
  local dir = tree({ ['a.rs'] = { 'fn a() {}' }, ['b.rs'] = { 'fn b() {}' } })
  child.cmd('edit ' .. dir .. '/a.rs')
  H.start_fake_lsp(child, { ['textDocument/diagnostic'] = pulled('old') }, { diagnosticProvider = {} })
  messages()
  child.lua([[
    _G.errors = {}
    vim.notify = function(msg, level) if level == vim.log.levels.ERROR then table.insert(_G.errors, msg) end end
    vim.lsp.diagnostic._refresh = nil
  ]])
  child.cmd('edit ' .. dir .. '/b.rs')
  child.cmd('edit ' .. dir .. '/a.rs')
  child.cmd('edit ' .. dir .. '/b.rs')
  child.cmd('edit ' .. dir .. '/a.rs')
  child.lua('vim.wait(100)')
  local errors = child.lua_get('_G.errors')
  eq({ #errors, errors[1]:match('^BufEnter diagnostic pull is dead') ~= nil }, { 1, true })
end

return T
