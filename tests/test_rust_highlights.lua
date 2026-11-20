-- The macro_rules overlay in queries/rust/highlights.scm, which guesses roles
-- by position in the body's flat token tree. Checked by the captures that
-- paint a word.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function() child.setup({ treesitter = true }) end,
    post_once = child.stop,
  },
})

local function captures(lines, needle) return H.captures(child, 'rust', lines, needle) end

T['a call in a macro_rules body is painted as a call'] = function()
  local caps = captures({ 'macro_rules! m { ($x:expr) => { helper($x) }; }' }, 'helper')
  eq(vim.tbl_contains(caps, 'rust:function.call'), true)
end

-- Before d88261f, the overlay also matched attribute args, another flat token
-- tree, so `params(...)` in a utoipa attribute was painted as a call.
T['attribute args get no macro body roles'] = function()
  local caps = captures({ '#[utoipa::path(get, params(Query), responses(Ok))]', 'fn f() {}' }, 'params')
  eq(vim.tbl_contains(caps, 'rust:function.call'), false)
end

return T
