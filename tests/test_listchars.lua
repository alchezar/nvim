-- options.lua shows every space and indent guide in visual and insert mode,
-- in the window being edited only.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ runtime = true })
      child.lua([[require('config.options')]])
    end,
    post_once = child.stop,
  },
})

-- Whether each window's listchars shows plain spaces.
local function spaces_shown()
  return child.lua([[
    local out = {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      out[#out + 1] = vim.wo[w].listchars:find('space:', 1, true) ~= nil
    end
    return out
  ]])
end

-- Before 5ffbb74, the expansion was set globally, so every window without a
-- local value of its own showed it too.
T['visual mode expands only the current window'] = function()
  child.cmd('vsplit')
  child.type_keys('v')
  eq(spaces_shown(), { true, false })
  child.type_keys('<Esc>')
  eq(spaces_shown(), { false, false })
end

return T
