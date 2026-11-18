-- plugins/treesitter.lua paints SQL keywords the sql grammar drops inside
-- sqlx queries. Checked by the screen: they must look like SELECT.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true })
      child.lua([[require('plugins.treesitter')]])
    end,
    post_once = child.stop,
  },
})

-- Screen attrs of `SELECT`, `word` and the first `id` in a Rust file of `line`.
local function attrs(line, word)
  local file = vim.fn.tempname() .. '.rs'
  vim.fn.writefile({ line }, file)
  child.cmd('edit ' .. file)
  return child.lua([[
    local line, word = ...
    vim.cmd('redraw')
    local function at(w) return vim.fn.screenattr(1, (line:find(w, 1, true))) end
    return { at('SELECT'), at(word), at('id') }
  ]], { line, word })
end

-- Before 173ca94, a SELECT without FROM (valid in Postgres) errored the sql
-- grammar, and WHERE showed up as a plain white variable.
T['WHERE in a FROM-less select reads as a keyword'] = function()
  local a = attrs('let r = sqlx::query!("SELECT id WHERE id = 1");', 'WHERE')
  eq({ where_is_keyword = a[2] == a[1], id_differs = a[3] ~= a[1] },
    { where_is_keyword = true, id_differs = true })
end

T['FOR UPDATE reads as keywords'] = function()
  local a = attrs('let r = sqlx::query!("SELECT id FROM t FOR UPDATE");', 'UPDATE')
  eq(a[2] == a[1], true)
end

T['lowercase rust where stays rust'] = function()
  local a = attrs('fn f<T>() where T: Copy {} // SELECT', 'where')
  eq(a[2] == a[1], false)
end

return T
