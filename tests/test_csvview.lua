-- CSV tables from plugins/csvview_setup.lua. The cursor line shows its raw
-- text, every other line the aligned layout.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'csvview.nvim' } })
      child.o.lines, child.o.columns = 10, 60
      child.lua([[require('plugins.csvview_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Screen text of rows 1-3 once csvview has drawn.
local function screen()
  return child.lua([[
    vim.wait(200)
    vim.cmd('redraw')
    local out = {}
    for row = 1, 3 do
      local line = {}
      for col = 1, 30 do line[#line + 1] = vim.fn.screenstring(row, col) end
      out[row] = vim.trim(table.concat(line))
    end
    return out
  ]])
end

T['the cursor line is raw, the rest aligned, and it follows the cursor'] = function()
  local file = vim.fn.tempname() .. '.csv'
  vim.fn.writefile({ 'name,n', 'a long name,1', 'b,22' }, file)
  child.cmd('edit ' .. file)
  local first = screen()
  child.type_keys('j')
  eq({ first, screen() }, {
    { 'name,n', 'a long name  │      1', 'b            │     22' },
    { 'name         │n', 'a long name,1', 'b            │     22' },
  })
end

return T
