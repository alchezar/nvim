-- Vim tips for the startify cow, parsed by config/vim_tips.lua from the
-- running nvim's `:help index`.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

local function tips() return child.lua_get([[require('config.vim_tips').get()]]) end

-- Trimmed `key = description` of every tip.
local function pairs_of(list)
  local out = {}
  for _, t in ipairs(list) do out[vim.trim(t[1])] = vim.trim(t[2]) end
  return out
end

T['a tip puts its key top left and its description bottom right'] = function()
  local list, bad = tips(), {}
  for _, t in ipairs(list) do
    local ok = #t[1] == #t[2] and #t[1] <= 48 and not t[1]:match('^%s') and not t[2]:match('%s$')
    if not ok then bad[#bad + 1] = t end
  end
  eq({ many = #list > 100, bad = bad }, { many = true, bad = {} })
end

T['a count goes before the key it repeats'] = function()
  local got = pairs_of(tips())
  eq({ got['NJ'], got['N]['] }, { 'Join N lines; default is 2', 'cursor N SECTIONS forward' })
end

T['ex commands, noise and arrow keys are left out'] = function()
  local bad = {}
  for key, desc in pairs(pairs_of(tips())) do
    if key:match('^:%a') or desc:find('same as') or desc:find('not used') or key:find('<Left>') then
      bad[#bad + 1] = key
    end
  end
  eq(bad, {})
end

return T
