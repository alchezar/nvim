-- float_backdrop dims the editor behind dialog floats with one full-screen
-- float, which must cover the screen and go away with the dialog.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua([[require('custom.float_backdrop')]])
    end,
    post_once = child.stop,
  },
})

-- Size of the backdrop once refresh settles, or false when there is none.
local function backdrop(expect_up)
  return child.lua([[
    local expect_up = ...
    local function find()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[w].float_backdrop then return w end
      end
    end
    vim.wait(1000, function() return (find() ~= nil) == expect_up end)
    local w = find()
    if not w then return false end
    local c = vim.api.nvim_win_get_config(w)
    return { c.width, c.height, vim.o.columns, vim.o.lines }
  ]], { expect_up })
end

local function open_dialog()
  return child.lua([[
    local buf = vim.api.nvim_create_buf(false, true)
    return vim.api.nvim_open_win(buf, true,
      { relative = 'editor', row = 2, col = 2, width = 20, height = 5 })
  ]])
end

T['covers the screen while a dialog is open, then goes'] = function()
  local dialog = open_dialog()
  eq(backdrop(true), { 82, 26, 80, 24 })
  child.api.nvim_win_close(dialog, true)
  eq(backdrop(false), false)
end

-- 8c3e15e: a resize while the dialog stayed open left the old size, so part
-- of the screen went undimmed.
T['follows a resize'] = function()
  open_dialog()
  backdrop(true)
  child.o.columns = 100
  eq(backdrop(true), { 102, 26, 100, 24 })
end

-- 8c3e15e: a dialog closed without autocmds (gitsigns' preview on cursor move)
-- left the backdrop up for good.
T['goes when the dialog closes silently'] = function()
  local dialog = open_dialog()
  backdrop(true)
  child.cmd('noautocmd call nvim_win_close(' .. dialog .. ', v:true)')
  child.type_keys('j')
  eq(backdrop(false), false)
end

return T
