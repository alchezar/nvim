-- blame.nvim heat map from plugins/blame_setup.lua. Every commit gets a color,
-- the oldest one end of the gradient and the newest the other.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'blame.nvim' } })
      -- Keep the setup args. blame.nvim holds its config in a local.
      child.lua([[
        local blame = require('blame')
        local setup = blame.setup
        blame.setup = function(args) _G.blame_args = args; return setup(args) end
        require('plugins.blame_setup')
      ]])
    end,
    post_once = child.stop,
  },
})

-- Colors blame paints `n` commits with, oldest first, plus the palette ends.
local function heat(n)
  return child.lua([[
    local n = ...
    local lines = {}
    for i = 1, n do
      lines[i] = { hash = ('%07d'):format(i) .. 'abcdef', author_time = 1000 + i }
    end
    local config = _G.blame_args
    require('blame.highlights').create_highlights_per_hash(lines, config)
    local out = {}
    for i = 1, n do
      local fg = vim.api.nvim_get_hl(0, { name = ('%07d'):format(i) }).fg
      out[i] = fg and ('#%06x'):format(fg) or 'none'
    end
    return { colors = out, first = config.colors[1]:lower(), last = config.colors[#config.colors]:lower() }
  ]], { n })
end

-- Before 35740c5, blame.nvim's spread inset both palette ends, so the oldest
-- commit got a washed-out color and past 2N+1 commits some got no fg at all.
T['many commits all get colors, ends on the gradient ends'] = function()
  local h = heat(50)
  eq(vim.tbl_contains(h.colors, 'none'), false)
  eq({ h.colors[1], h.colors[50] }, { h.first, h.last })
end

return T
