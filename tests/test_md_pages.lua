-- Approximate A4 page count of a markdown buffer, from custom/md_pages.lua,
-- shown in fishbone's statusline.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'fishbone.nvim' } })
      child.o.lines, child.o.columns = 20, 120
      child.lua([[require('plugins.fishbone_setup'); require('custom.md_pages')]])
    end,
    post_once = child.stop,
  },
})

-- Pages of a markdown buffer of `lines`.
local function pages(lines)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  return child.lua_get([[require('custom.md_pages').pages()]])
end

-- `n` copies of `line`.
local function rep(line, n)
  local out = {}
  for i = 1, n do out[i] = line end
  return out
end

T['a page holds 54 printed lines'] = function()
  eq({ pages({ 'one' }), pages(rep('- item', 54)), pages(rep('- item', 55)) }, { 1, 1, 2 })
end

T['a long line costs the rows it wraps to'] = function()
  -- 112 columns wrap to 2 rows of 90.
  local long = '- ' .. ('wordwordw '):rep(11)
  eq({ pages(rep(long, 27)), pages(rep(long, 28)) }, { 1, 2 })
end

T['hard-wrapped prose reflows into its paragraph'] = function()
  eq({ pages(rep('short prose line', 60)), pages(rep('    code line', 60)) }, { 1, 2 })
end

T['each fenced line prints on its own'] = function()
  local lines = rep('code', 60)
  table.insert(lines, 1, '```')
  lines[#lines + 1] = '```'
  eq(pages(lines), 2)
end

-- The statusline names the count for markdown only.
T['the statusline shows the count for markdown'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, rep('- item', 60))
  local plain = child.lua_get([[require('fishbone').render()]])
  child.cmd('setlocal filetype=markdown')
  local md = child.lua_get([[require('fishbone').render()]])
  eq({ plain:find('\u{f0219}', 1, true) ~= nil, md:find('\u{f0219} 2', 1, true) ~= nil }, { false, true })
end

return T
