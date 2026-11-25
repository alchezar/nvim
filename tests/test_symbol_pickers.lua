-- The file structure and type declaration pickers from config/utils.lua, fed
-- by a fake server that knows the symbols of one rust file.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true, plugins = { 'plenary.nvim', 'telescope.nvim' } })
      child.o.lines, child.o.columns = 30, 160
      child.lua([[require('plugins.telescope_setup')]])
    end,
    post_once = child.stop,
  },
})

local SRC = {
  'pub struct Point {',
  '    x: i32,',
  '}',
  'enum Dir { Up }',
  'impl Point {',
  '    pub fn len(&self) -> i32 { 0 }',
  '}',
  '#[tokio::test]',
  'async fn checks() {}',
  'fn helper() {}',
}

local function span(from, to)
  return { start = { line = from - 1, character = 0 }, ['end'] = { line = to - 1, character = 1 } }
end

-- A symbol of `kind` spanning lines `from`..`to` (1-based), its name on the
-- last line as rust-analyzer has it for an item under attributes.
local function sym(name, kind, from, to, children)
  return { name = name, kind = kind, range = span(from, to), selectionRange = span(to, to), children = children }
end

-- Opens SRC as src/lib.rs with its symbols known to a fake server.
local function project()
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/')))
  dir = dir .. '/' .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  vim.fn.mkdir(dir .. '/src', 'p')
  vim.fn.writefile(SRC, dir .. '/src/lib.rs')
  child.lua('vim.cmd.cd(...)', { dir })
  child.cmd('edit src/lib.rs')
  child.lua('vim.treesitter.start()')
  local K = { Struct = 23, Field = 8, Enum = 10, EnumMember = 22, Object = 19, Function = 12 }
  local symbols = {
    sym('Point', K.Struct, 1, 1, { sym('x', K.Field, 2, 2) }),
    sym('Dir', K.Enum, 4, 4, { sym('Up', K.EnumMember, 4, 4) }),
    sym('impl Point', K.Object, 5, 5, { sym('len', K.Function, 6, 6) }),
    sym('checks', K.Function, 8, 9),
    sym('helper', K.Function, 10, 10),
  }
  local uri = vim.uri_from_fname(dir .. '/src/lib.rs')
  local function info(name, kind, line)
    return { name = name, kind = kind, location = { uri = uri, range = span(line, line) } }
  end
  H.start_fake_lsp(child, {
    ['textDocument/documentSymbol'] = symbols,
    ['workspace/symbol'] = { info('Point', K.Struct, 1), info('Dir', K.Enum, 4), info('helper', K.Function, 10) },
  }, { documentSymbolProvider = true, workspaceSymbolProvider = true })
  return dir
end

-- Picker rows once it has any, icons spelled out and spaces squeezed.
local function rows(open)
  return child.lua([[
    loadstring(...)()
    local out
    vim.wait(2000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.bo[b].filetype == 'TelescopeResults' then
          out = vim.tbl_filter(function(r) return r ~= '' end, vim.api.nvim_buf_get_lines(b, 0, -1, false))
          return #out > 0
        end
      end
    end)
    for i, r in ipairs(out or {}) do
      r = r:gsub('\u{ea70}', 'pub'):gsub('\u{eae7}', 'priv'):gsub('[\128-\255]+', ''):gsub('%s+', ' ')
      out[i] = vim.trim(r)
    end
    return out
  ]], { open })
end

-- The file structure picker over SRC with the cursor on `cursor_line`. Rows
-- are found by a symbol's name, so the checks hold across row layouts; the
-- `impl Point` row never stands for Point.
local function structure(cursor_line)
  project()
  child.api.nvim_win_set_cursor(0, { cursor_line or 1, 0 })
  local list = rows([[require('config.utils').document_symbols()]])
  local function row(name)
    for _, r in ipairs(list) do
      if r:find('%f[%w]' .. name .. '%f[^%w]') and not r:find('impl') then return r end
    end
    return false
  end
  return row, list
end

local function has(r, word) return r and r:find('%f[%w]' .. word .. '%f[^%w]') ~= nil end

T['a rust symbol shows whether it is pub'] = function()
  local row = structure()
  eq({ has(row('Point'), 'pub'), has(row('Dir'), 'priv'), has(row('len'), 'pub'), has(row('helper'), 'priv') },
    { true, true, true, true })
end

T['a row leads with its line number'] = function()
  local row = structure()
  eq({ row('Point'):match('%d+'), row('checks'):match('%d+'), row('helper'):match('%d+') }, { '1', '9', '10' })
end

T['a fn under a test attribute is labelled test'] = function()
  local row = structure()
  eq({ has(row('checks'), 'test'), has(row('helper'), 'test') }, { true, false })
end

T['a fn of an impl is labelled method'] = function()
  local row = structure()
  eq({ has(row('len'), 'method'), has(row('helper'), 'function') }, { true, true })
end

T['struct fields stay out'] = function()
  local row = structure()
  eq({ row('x'), has(row('Point'), 'struct') }, { false, true })
end

T['enum variants stay out'] = function()
  local row = structure()
  eq({ row('Up'), has(row('Dir'), 'enum') }, { false, true })
end

T['the picker starts on the symbol around the cursor'] = function()
  local _, list = structure(7)
  local selected = vim.tbl_filter(function(r) return r:sub(1, 1) == '>' end, list)
  eq(#selected == 1 and has(selected[1], 'len'), true)
end

T['type declarations list only the types of the project'] = function()
  project()
  local list = rows([[require('config.utils').type_declarations()]])
  eq({ #list, has(list[1], 'Point'), has(list[2], 'Dir') }, { 2, true, true })
end

T['a type declaration row shows its kind and place'] = function()
  project()
  eq(rows([[require('config.utils').type_declarations()]]),
    { '> struct Point lib.rs:1\\src', 'enum Dir lib.rs:4\\src' })
end

-- Markdown has no server here; the outline comes from the buffer itself.
T['a markdown file lists its headings and enter jumps to one'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { '# Guide', 'Intro.', '## Install', 'Steps.', '## Usage' })
  child.cmd('setfiletype markdown')
  child.api.nvim_win_set_cursor(0, { 4, 0 })
  local list = rows([[require('config.utils').document_symbols()]])
  child.cmd('stopinsert')
  child.type_keys('<CR>')
  child.lua('vim.wait(100)')
  eq({ list, child.api.nvim_win_get_cursor(0)[1] },
    { { '1 Guide', '> 3 Install', '5 Usage' }, 3 })
end

return T
