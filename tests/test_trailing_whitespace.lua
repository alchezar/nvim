-- Trailing whitespace as HINT diagnostics, from custom/trailing_whitespace.lua.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua([[require('custom.trailing_whitespace')]])
    end,
    post_once = child.stop,
  },
})

-- Its diagnostics in the current buffer as `row:col-end_col severity`.
local function hints()
  return child.lua([[
    local ns = vim.api.nvim_get_namespaces()['user_trailing_whitespace']
    return vim.tbl_map(function(d)
      return ('%d:%d-%d %s'):format(d.lnum, d.col, d.end_col, vim.diagnostic.severity[d.severity])
    end, vim.diagnostic.get(0, { namespace = ns }))
  ]])
end

local function open(lines)
  local file = vim.fn.tempname()
  vim.fn.writefile(lines, file)
  child.cmd('edit ' .. file)
end

T['trailing spaces and tabs are hints over just the whitespace'] = function()
  open({ 'one  ', 'two', 'three\t', '   ' })
  eq(hints(), { '0:3-5 HINT', '2:5-6 HINT', '3:0-3 HINT' })
end

T['a line is flagged once typing on it stops'] = function()
  open({ 'one' })
  child.type_keys('A  ')
  local typing = hints()
  child.type_keys('<Esc>')
  eq({ typing, hints() }, { {}, { '0:3-5 HINT' } })
end

T['cleaning a line clears its hint'] = function()
  open({ 'one  ', 'two  ' })
  child.cmd([[1s/\s\+$//]])
  eq(hints(), { '1:3-5 HINT' })
end

T['scratch buffers are left alone'] = function()
  child.cmd('enew | setlocal buftype=nofile')
  child.type_keys('ione  ', '<Esc>')
  eq(hints(), {})
end

return T
