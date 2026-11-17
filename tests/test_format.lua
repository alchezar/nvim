-- Formatting rules. Nothing wraps while typing, Q (formatexpr) wraps prose
-- at 80 and aligns tables, and :w keeps tables as typed.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({ runtime = true, plugins = { 'conform.nvim' }, treesitter = true })
      child.lua([[require('config.options')]])
    end,
    post_once = child.stop,
  },
})

local function markdown(lines)
  local file = vim.fn.tempname() .. '.md'
  vim.fn.writefile(lines, file)
  child.cmd('edit ' .. file)
  return file
end

local function buf_lines() return child.api.nvim_buf_get_lines(0, 0, -1, false) end

local LONG = ('word '):rep(25) .. 'end'

-- 5212f2d: the markdown ftplugin re-added 't', so lines broke while typing.
T['typing past textwidth does not wrap'] = function()
  markdown({ '' })
  child.type_keys('i', LONG, '<Esc>')
  eq(buf_lines(), { LONG })
end

-- 5212f2d: built-in gq joined the table rows into the paragraph.
T['Q wraps prose and leaves table rows apart'] = function()
  markdown({ LONG, '', '| a | b |', '| --- | --- |', '| 1 | 2 |' })
  child.type_keys('gg', 'gqG')
  local got = buf_lines()
  local rows = vim.tbl_filter(function(l) return l:sub(1, 1) == '|' end, got)
  eq({ #got[1] <= 80, #rows, got[#got]:sub(1, 1) }, { true, 3, '|' })
end

T['Q aligns a table'] = function()
  markdown({ '|a|bb|', '|-|:-:|', '|ccc|d|' })
  child.type_keys('gg', 'gqG')
  eq(buf_lines(), { '| a   | bb  |', '| --- | :-: |', '| ccc |  d  |' })
end

T[':w keeps tables as typed while prettier formats the rest'] = function()
  local file = markdown({ '# Title', '*   item', '', '|a|bb|', '|-|-|', '|ccc|d|' })
  child.lua([[require('plugins.formatting')]])
  child.cmd('write')
  eq(vim.fn.readfile(file), { '# Title', '', '- item', '', '|a|bb|', '|-|-|', '|ccc|d|' })
end

return T
