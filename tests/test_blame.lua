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

-- Before 4ebcd76, both panes got a scroll step of 25, which a pane shorter
-- than that rejects with E49.
T['blame in a short window gives both panes one step'] = function()
  child.o.lines = 20
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'one', 'two', 'three' }, dir .. '/f.txt')
  for _, args in ipairs({ { 'init', '-q' }, { 'add', '.' }, { 'commit', '-q', '-m', 'c' } }) do
    local res = vim.system(vim.list_extend({ 'git', '-c', 'user.name=t', '-c', 'user.email=t@t' }, args), {
      cwd = dir,
      env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
    }):wait()
    assert(res.code == 0, res.stderr)
  end
  local got = child.lua([[
    vim.cmd.edit(... .. '/f.txt')
    vim.cmd('BlameToggle window')
    vim.wait(3000, function() return #vim.api.nvim_tabpage_list_wins(0) > 1 end)
    -- The step is pinned from a scheduled callback; let it and its kin run.
    for _ = 1, 3 do
      local done = false
      vim.schedule(function() done = true end)
      vim.wait(1000, function() return done end)
    end
    local steps = {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.wo[w].scrollbind then steps[#steps + 1] = vim.wo[w].scroll end
    end
    return { error = vim.fn.execute('messages'):match('E%d+: [^\n]*'), panes = #steps, same = steps[1] == steps[2] }
  ]], { dir })
  eq(got, { panes = 2, same = true })
end

-- Before 35740c5, blame.nvim's spread inset both palette ends, so the oldest
-- commit got a washed-out color and past 2N+1 commits some got no fg at all.
T['many commits all get colors, ends on the gradient ends'] = function()
  local h = heat(50)
  eq(vim.tbl_contains(h.colors, 'none'), false)
  eq({ h.colors[1], h.colors[50] }, { h.first, h.last })
end

return T
