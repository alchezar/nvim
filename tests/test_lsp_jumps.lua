-- Jumps from config/utils.lua that lean on a server: clangd's source/header
-- switch and `gI` from an impl method to the trait that declares it.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua([[
        _G.notes = {}
        vim.notify = function(msg) table.insert(_G.notes, msg) end
      ]])
    end,
    post_once = child.stop,
  },
})

-- A dir holding `files` (name -> lines), resolved.
local function project(files)
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  vim.fn.mkdir(dir, 'p')
  for name, lines in pairs(files) do vim.fn.writefile(lines, dir .. '/' .. name) end
  return dir
end

-- File name and cursor once `fn` of utils has run and settled.
local function after(fn)
  child.lua([[require('config.utils')[...]() vim.wait(300)]], { fn })
  return { vim.fn.fnamemodify(child.api.nvim_buf_get_name(0), ':t'), child.api.nvim_win_get_cursor(0)[1] }
end

T['clangd switches a source to its header'] = function()
  local dir = project({ ['a.cpp'] = { 'int a;' }, ['a.h'] = { 'extern int a;' } })
  child.cmd('edit ' .. dir .. '/a.cpp')
  H.start_fake_lsp(child, { ['textDocument/switchSourceHeader'] = vim.uri_from_fname(dir .. '/a.h') }, {}, 'clangd')
  eq(after('switch_source_header'), { 'a.h', 1 })
end

T['without clangd the switch only warns'] = function()
  local dir = project({ ['a.cpp'] = { 'int a;' } })
  child.cmd('edit ' .. dir .. '/a.cpp')
  eq({ after('switch_source_header'), child.lua_get('_G.notes') }, { { 'a.cpp', 1 }, { 'clangd not attached' } })
end

-- Before 0b88971, an `impl<T>` line failed to parse, and a path-qualified trait
-- was looked up by its first segment.
local IMPL = { 'impl<T> geo::Shape<T> for Sq {', '    fn area(&self) -> f64 { 1.0 }', '}' }

T['gI goes from an impl method to the trait method in the same file'] = function()
  local lines = { 'trait Shape<T> {', '    fn name(&self);', '    fn area(&self) -> f64;', '}' }
  local dir = project({ ['a.rs'] = vim.list_extend(lines, IMPL) })
  child.cmd('edit ' .. dir .. '/a.rs')
  child.api.nvim_win_set_cursor(0, { 6, 8 })
  eq(after('go_to_interface'), { 'a.rs', 3 })
end

T['gI finds a trait in another file through workspace symbols'] = function()
  local dir = project({
    ['impls.rs'] = IMPL,
    ['shapes.rs'] = { '// Shapes.', 'pub trait Shape<T> {', '    fn area(&self) -> f64;', '}' },
  })
  child.cmd('edit ' .. dir .. '/impls.rs')
  local at = { start = { line = 1, character = 0 }, ['end'] = { line = 1, character = 5 } }
  H.start_fake_lsp(child, {
    ['workspace/symbol'] = {
      { name = 'Shape', kind = 13, location = { uri = vim.uri_from_fname(dir .. '/impls.rs'), range = at } },
      { name = 'Shape', kind = 11, location = { uri = vim.uri_from_fname(dir .. '/shapes.rs'), range = at } },
    }
  }, { workspaceSymbolProvider = true })
  child.api.nvim_win_set_cursor(0, { 2, 8 })
  eq(after('go_to_interface'), { 'shapes.rs', 3 })
end

T['gI outside an impl of a trait only warns'] = function()
  local dir = project({ ['a.rs'] = { 'impl Sq {', '    fn area(&self) {}', '}' } })
  child.cmd('edit ' .. dir .. '/a.rs')
  child.api.nvim_win_set_cursor(0, { 2, 8 })
  eq({ after('go_to_interface'), child.lua_get('_G.notes') },
    { { 'a.rs', 2 }, { 'Not inside an `impl Trait for ...` block' } })
end

return T
