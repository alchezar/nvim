-- plugins/virt_column_setup.lua carries the 81/101 rule across LSP codelens
-- virtual lines in visual mode, which virt-column itself can't reach.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'virt-column.nvim' } })
      child.o.lines, child.o.columns = 8, 110
      child.lua([[require('plugins.virt_column_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Screen text at columns 81 and 101 of the codelens row above line 1.
local function rule_on_lens()
  return child.lua([[
    vim.cmd('redraw')
    return { vim.fn.screenstring(1, 81), vim.fn.screenstring(1, 101) }
  ]])
end

-- Before f07b98f, the rule broke off at every "N references" line above a
-- rust-analyzer item, leaving a gap in the column guide.
T['visual mode draws the rule through a codelens line'] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'fn main() {}', 'x', 'y' })
    local ns = vim.api.nvim_create_namespace('nvim.lsp.codelens.test')
    vim.api.nvim_buf_set_extmark(0, ns, 0, 0, {
      virt_lines = { { { '3 references', 'LspCodeLens' } } },
      virt_lines_above = true,
    })
    vim.fn.winrestview({ topfill = 1 })
  ]])
  eq(rule_on_lens(), { ' ', ' ' })
  child.type_keys('V')
  eq(rule_on_lens(), { '\u{258F}', '\u{258F}' })
  child.type_keys('<Esc>')
  eq(rule_on_lens(), { ' ', ' ' })
end

return T
