-- gitsigns helpers in config/utils.lua. The hunk float is clamped to the
-- screen width and soft-wraps, so it must grow to show every wrapped row;
-- ]g and [g walk the hunks.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'gitsigns.nvim' } })
      child.o.lines, child.o.columns = 30, 60
      child.lua([[require('gitsigns').setup()]])
    end,
    post_once = child.stop,
  },
})

local function git(dir, ...)
  local res = vim.system({ 'git', '-c', 'user.name=t', '-c', 'user.email=t@t', ... }, {
    cwd = dir,
    env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
  }):wait()
  assert(res.code == 0, res.stderr)
end

-- A committed file whose working copy turns line 2 into a long one.
local function repo_with_long_change()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local dir = vim.uv.fs_realpath(tmp) or tmp
  git(dir, 'init', '-q')
  vim.fn.writefile({ 'one', 'two', 'three' }, dir .. '/f.txt')
  git(dir, 'add', '.')
  git(dir, 'commit', '-q', '-m', 'base')
  vim.fn.writefile({ 'one', ('long words here '):rep(12), 'three' }, dir .. '/f.txt')
  return dir
end

-- Before 5641486, the float kept gitsigns' height of one row per line, so the
-- wrapped rows past it were cut off.
T['preview shows every wrapped row'] = function()
  local dir = repo_with_long_change()
  child.lua('vim.cmd.cd(...)', { dir })
  child.cmd('edit f.txt')
  local got = child.lua([[
    local buf = vim.api.nvim_get_current_buf()
    vim.wait(3000, function() return require('gitsigns.cache').cache[buf] ~= nil end)
    vim.wait(3000, function()
      local h = require('gitsigns').get_hunks(buf)
      return h and #h > 0
    end)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require('config.utils').gitsigns_preview_hunk()
    local win
    vim.wait(3000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[w].gitsigns_preview ~= nil then win = w end
      end
      return win ~= nil
    end)
    assert(win, 'no preview float')
    -- gitsigns opens the float async; the clamp lands a few ticks later.
    vim.wait(3000, function() return vim.api.nvim_win_get_width(win) <= 48 end)
    return {
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
      rows = vim.api.nvim_win_text_height(win, {}).all,
    }
  ]])
  eq({ fits = got.width <= 48, all_rows = got.height == got.rows }, { fits = true, all_rows = true })
end

T[']g and [g walk the hunks of the file'] = function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local dir = vim.uv.fs_realpath(tmp) or tmp
  git(dir, 'init', '-q')
  local lines = {}
  for i = 1, 20 do lines[i] = 'line ' .. i end
  vim.fn.writefile(lines, dir .. '/f.txt')
  git(dir, 'add', '.')
  git(dir, 'commit', '-q', '-m', 'base')
  lines[5], lines[15] = 'five', 'fifteen'
  vim.fn.writefile(lines, dir .. '/f.txt')
  child.lua('vim.cmd.cd(...)', { dir })
  child.cmd('edit f.txt')
  eq(child.lua([[
    local buf, u = vim.api.nvim_get_current_buf(), require('config.utils')
    vim.wait(3000, function()
      local h = require('gitsigns').get_hunks(buf)
      return h and #h == 2
    end)
    local function at(jump)
      u[jump]()
      vim.wait(200)
      return vim.api.nvim_win_get_cursor(0)[1]
    end
    return { at('git_hunk_next'), at('git_hunk_next'), at('git_hunk_prev') }
  ]]), { 5, 15, 5 })
end

return T
