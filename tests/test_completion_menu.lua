-- nvim-cmp rows from plugins/completion_setup.lua. A long rust-analyzer
-- signature becomes `name(args) -> Ret`, cut short whatever the screen width.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-cmp', 'LuaSnip' } })
      child.o.columns = 200
      child.lua([[require('plugins.completion_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Menu row for an item whose labelDetails are `ld`.
local function row(abbr, ld)
  return child.lua([[
    local abbr, ld = ...
    local entry = { get_completion_item = function() return { labelDetails = ld } end }
    local item = require('cmp').get_config().formatting.format(entry, { abbr = abbr, kind = 'Function' })
    return { abbr = item.abbr, width = vim.fn.strdisplaywidth(item.abbr), menu = item.menu }
  ]], { abbr, ld })
end

T['a fn signature shows from its name on'] = function()
  local got = row('add', { description = 'pub const fn add(a: i32, b: i32) -> i32' })
  eq(got.abbr, 'add(a: i32, b: i32) -> i32')
end

-- Before c98ad12, the cap was half the screen, so on a wide screen one long
-- signature stretched the menu and the docs window overlapped the names.
T['a long signature is cut on a wide screen'] = function()
  local args = {}
  for i = 1, 12 do args[#args + 1] = ('arg%d: Option<String>'):format(i) end
  local got = row('build', { description = 'pub fn build(' .. table.concat(args, ', ') .. ') -> Self' })
  eq(got.width <= 50, true)
end

T['trait origin goes to the menu column'] = function()
  local got = row('fmt', { description = 'fn fmt(&self) -> Result', detail = '(as Display)' })
  eq(got.menu, '(as Display)')
end

return T
