-- plugins/autopairs_setup.lua: in Rust `<` after a type name closes itself,
-- while a comparison keeps its lone `<`.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-autopairs' } })
      child.lua([[require('plugins.autopairs_setup')]])
    end,
    post_once = child.stop,
  },
})

-- The line left after typing `keys` in a fresh buffer of filetype `ft`.
local function typed(ft, keys)
  child.cmd('enew | setfiletype ' .. ft)
  -- One key at a time, as typed; a batch inserts its plain chars only after
  -- autopairs looked at the line. A bare `<` would open a key name.
  local chars = vim.tbl_map(function(c) return c == '<' and '<LT>' or c end, vim.split(keys, ''))
  child.type_keys('i', chars, '<Esc>')
  return child.api.nvim_get_current_line()
end

T['rust generics close themselves and > steps over'] = function()
  eq({ typed('rust', 'Vec<'), typed('rust', 'Vec<u8>;'), typed('rust', 'iter::<') },
    { 'Vec<>', 'Vec<u8>;', 'iter::<>' })
end

T['a comparison and other languages keep a lone <'] = function()
  eq({ typed('rust', 'a < b'), typed('lua', 'f<') }, { 'a < b', 'f<' })
end

return T
