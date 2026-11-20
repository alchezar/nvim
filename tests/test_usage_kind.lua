-- Read/write marks in the LSP references picker (config/usage_kind.lua). A
-- usage is a write when the syntax around it assigns or `&mut` borrows it.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function() child.setup({ treesitter = true }) end,
    post_once = child.stop,
  },
})

-- Access kind of every whole-word `name` in a file of `lines`, in order.
local function kinds(ext, lines, name)
  return child.lua([[
    local ext, lines, name = ...
    local file = vim.fn.tempname() .. '.' .. ext
    vim.fn.writefile(lines, file)
    local out = {}
    for row, line in ipairs(lines) do
      for col in line:gmatch('()%f[%w_]' .. name .. '%f[^%w_]') do
        out[#out + 1] = require('config.usage_kind').classify(file, row, col)
      end
    end
    return out
  ]], { ext, lines, name })
end

-- `body` as the inside of a rust function.
local function rust(body) return { 'fn f() {', body, '}' } end

T['an assignment writes its target and reads its value'] = function()
  eq(kinds('rs', rust('x = x + 1; x += x;'), 'x'), { 'write', 'read', 'write', 'read' })
end

T['a mutable borrow writes, a shared one reads'] = function()
  eq(kinds('rs', rust('g(&mut x); g(&x);'), 'x'), { 'write', 'read' })
end

T['a field write writes the field and reads its owner'] = function()
  local lines = rust('s.n = 1; s.n += 1; g(&mut s.n);')
  eq({ kinds('rs', lines, 's'), kinds('rs', lines, 'n') },
    { { 'read', 'read', 'read' }, { 'write', 'write', 'write' } })
end

T['a struct literal writes its fields'] = function()
  local lines = rust('let a = S { n: v }; let b = S { n };')
  eq({ kinds('rs', lines, 'n'), kinds('rs', lines, 'v') }, { { 'write', 'write' }, { 'read' } })
end

T['increments write'] = function()
  eq({ kinds('c', { 'void f() { x++; --x; }' }, 'x'), kinds('js', { 'x++; --x;' }, 'x') },
    { { 'write', 'write' }, { 'write', 'write' } })
end

-- Before 8463910, an index counted as written along with its element.
T['an index is only read where its element is written'] = function()
  eq(kinds('rs', rust('a[i] = 1; a[i][i] += 1; g(&mut a[i]);'), 'i'), { 'read', 'read', 'read', 'read' })
end

-- Before 8463910, `&mut` wrote everything inside the borrowed expression.
T['values that build a mutably borrowed temporary are only read'] = function()
  eq(kinds('rs', rust('g(&mut P::new(x)); g(&mut S { n: x });'), 'x'), { 'read', 'read' })
end

-- Before 8463910, the owner of a field or element written in c, javascript or
-- python counted as written, and python's `x += 1` as read.
T['other languages write the field or element, not its owner'] = function()
  eq({
    c = kinds('c', { 'void f() { a[i] = 1; }' }, 'a'),
    js = kinds('js', { 'o.p = 1; a[0] = 1; o.p++;' }, '[oa]'),
    py = kinds('py', { 'o.p = 1', 'a[0] = 1' }, '[oa]'),
    py_aug = kinds('py', { 'x += 1', 'o.p += 1' }, '[xp]'),
  }, {
    c = { 'read' },
    js = { 'read', 'read', 'read' },
    py = { 'read', 'read' },
    py_aug = { 'write', 'write' },
  })
end

return T
