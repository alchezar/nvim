-- Ukrainian-layout keys from plugins/langmapper_setup.lua, checked against
-- what their latin twins do. config/options.lua maps j/k to gj/gk.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ runtime = true, plugins = { 'langmapper.nvim' } })
      child.o.lines, child.o.columns = 10, 30
      child.lua([[
        require('config.options')
        require('plugins.langmapper_setup')
        vim.cmd('doautocmd VimEnter')
        vim.wo.wrap = true
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { ('word '):rep(20), 'next' })
      ]])
    end,
    post_once = child.stop,
  },
})

-- Line and screen row the cursor reaches from the top with `key`.
local function step(key)
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys(key)
  return child.lua([[return { vim.fn.line('.'), vim.fn.winline() }]])
end

-- Before d52ea71, langmapper bound о and л to the builtin j and k, so on a
-- wrapped line they jumped whole buffer lines.
T['о and л walk a wrapped line by screen row, like j and k'] = function()
  eq({ step('о'), step('Gл') }, { step('j'), step('Gk') })
end

return T
