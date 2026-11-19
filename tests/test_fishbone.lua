-- fishbone's position bar, set up by plugins/fishbone_setup.lua, marks the
-- lines that hold a bookmark extmark from custom/bookmarks.lua.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'fishbone.nvim' } })
      child.o.lines, child.o.columns = 20, 80
      child.lua([[require('plugins.fishbone_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Before 35aa7aa, fishbone only read vim marks and marks.nvim, so bookmarks
-- living as extmarks never showed in its mark layer.
T['a bookmark extmark changes the bar'] = function()
  local bars = child.lua([[
    local lines = {}
    for i = 1, 200 do lines[i] = 'line ' .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    local fishbone = require('fishbone')
    local before = fishbone.render()
    local ns = vim.api.nvim_create_namespace('user_bookmarks')
    vim.api.nvim_buf_set_extmark(0, ns, 149, 0, { sign_text = '1' })
    -- Nudge the buffer so a render cache keyed on it can't answer from before.
    vim.api.nvim_buf_set_lines(0, 199, 200, false, { 'line 200' })
    return { before, fishbone.render() }
  ]])
  eq(bars[1] ~= bars[2], true)
end

return T
