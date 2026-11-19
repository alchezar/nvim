-- utils.dim_cursorline_while_scrolling, wired up for Neovide in
-- config/neovide.lua. A window's cursorline goes off while it scrolls and
-- comes back once the scroll settles.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.o.lines, child.o.columns = 20, 60
      child.lua([[
        require('config.utils').dim_cursorline_while_scrolling()
        local lines = {}
        for i = 1, 200 do lines[i] = 'line ' .. i end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      ]])
    end,
    post_once = child.stop,
  },
})

-- Scroll the current window and report its cursorline right after the scroll
-- event and again once it settles.
-- WinScrolled fires from the main loop, so each step is its own request.
local function scroll()
  child.lua([[vim.wo.cursorline = true]])
  child.type_keys('5<C-e>')
  local during = child.lua([[
    vim.wait(100, function() return not vim.wo.cursorline end, 5)
    return vim.wo.cursorline
  ]])
  child.lua([[if _G.while_hidden then _G.while_hidden() end]])
  local after = child.lua([[
    vim.wait(400, function() return vim.wo.cursorline end, 20)
    return vim.wo.cursorline
  ]])
  return { during = during, after = after }
end

T['a tree-like window hides its cursorline only while scrolling'] = function()
  child.lua([[vim.bo.buftype = 'nofile']])
  eq(scroll(), { during = false, after = true })
end

-- Before 24a5159, only special windows (buftype set) were handled, so a code
-- window kept its cursorline and Neovide smeared it through the scroll.
T['a code window hides its cursorline too'] = function()
  eq(scroll(), { during = false, after = true })
end

-- Before 24a5159, the restore ran even after someone else had set cursorline
-- mid-scroll, freezing a stale cursorline back on.
T['a cursorline turned off mid-scroll stays off'] = function()
  child.lua([[
    vim.bo.buftype = 'nofile'
    _G.while_hidden = function() vim.wo.cursorline = false end
  ]])
  eq(scroll(), { during = false, after = false })
end

return T
