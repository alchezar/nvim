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

-- A child whose `im-select` reports `layout`, langmapper set up after it.
-- utils reads PATH for im-select once, when it loads.
local function on_layout(layout)
  local bin = vim.fn.tempname()
  vim.fn.mkdir(bin, 'p')
  vim.fn.writefile({ '#!/bin/sh', 'echo "$LAYOUT"' }, bin .. '/im-select')
  vim.uv.fs_chmod(bin .. '/im-select', 493)
  child.setup({ runtime = true, plugins = { 'langmapper.nvim' } })
  child.o.lines, child.o.columns = 10, 60
  child.lua([[
    local bin, layout = ...
    vim.env.PATH, vim.env.LAYOUT = bin .. ':' .. vim.env.PATH, layout
    require('config.options')
    require('plugins.langmapper_setup')
    vim.cmd('doautocmd VimEnter')
    local want = layout:find('Ukrainian') and '$' or ';'
    vim.wait(2000, function() return require('config.utils').key_dollar() == want end)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '  one two three', 'x' })
  ]], { bin, layout })
end

T['on the Ukrainian layout Shift+4, 6 and 2 do $, ^ and @'] = function()
  on_layout('com.apple.keylayout.Ukrainian-PC')
  child.api.nvim_win_set_cursor(0, { 1, 4 })
  child.type_keys(';')
  local dollar = child.api.nvim_win_get_cursor(0)[2]
  child.type_keys(':')
  local caret = child.api.nvim_win_get_cursor(0)[2]
  child.fn.setreg('q', 'jdd')
  child.type_keys('gg', '"q')
  eq({ dollar, caret, child.api.nvim_buf_get_lines(0, 0, -1, false) }, { 14, 2, { '  one two three' } })
end

T['on a latin layout ; : and " keep their own jobs'] = function()
  on_layout('com.apple.keylayout.ABC')
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys('fe', ';')
  local again = child.api.nvim_win_get_cursor(0)[2]
  child.type_keys('"', 'a', 'yy')
  local yanked = child.fn.getreg('a')
  child.type_keys(':')
  eq({ again, yanked, child.api.nvim_get_mode().mode }, { 13, '  one two three\n', 'c' })
end

return T
