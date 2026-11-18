-- custom/branch_review diffs every file against a chosen base through
-- gitsigns. Checked by the hunks gitsigns reports once the base is set.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'gitsigns.nvim', 'nvim-tree.lua' } })
      child.lua([[require('gitsigns').setup(); require('custom.branch_review')]])
    end,
    post_once = child.stop,
  },
})

-- git in `dir`, free of the user's own config (signing, hooks, editors).
local function git(dir, ...)
  local res = vim.system({ 'git', '-c', 'user.name=t', '-c', 'user.email=t@t', ... }, {
    cwd = dir,
    env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
  }):wait()
  assert(res.code == 0, res.stderr)
end

-- Hunks of `file` as `type:start` once gitsigns settles on the review base.
local function hunks_after_review(dir, file)
  child.lua('vim.cmd.cd(...)', { dir })
  child.cmd('edit ' .. file)
  return child.lua([[
    local gs, buf = require('gitsigns'), vim.api.nvim_get_current_buf()
    -- The buffer joins gitsigns' cache only when attach completes; a base set
    -- before that is lost.
    vim.wait(3000, function() return require('gitsigns.cache').cache[buf] ~= nil end)
    require('custom.branch_review').toggle('HEAD~1')
    local out
    vim.wait(3000, function()
      local h = gs.get_hunks(buf)
      if h and #h > 0 then
        out = vim.tbl_map(function(x) return x.type .. ':' .. x.added.start end, h)
      end
      return out ~= nil
    end)
    return out or {}
  ]])
end

-- 9e86e1f fixed a renamed file getting no base (an absolute path looked up in
-- a map keyed by repo paths). gitsigns resolves it itself now; this guards it.
T['a file renamed since the base diffs against its old name'] = function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, 'p')
  local dir = vim.uv.fs_realpath(tmp) or tmp
  git(dir, 'init', '-q')
  vim.fn.writefile({ 'one', 'two', 'three', 'four', 'five' }, dir .. '/a.txt')
  git(dir, 'add', '.')
  git(dir, 'commit', '-q', '-m', 'base')
  git(dir, 'mv', 'a.txt', 'b.txt')
  vim.fn.writefile({ 'one', 'two', 'THREE', 'four', 'five' }, dir .. '/b.txt')
  git(dir, 'commit', '-q', '-am', 'rename and edit')
  eq(hunks_after_review(dir, dir .. '/b.txt'), { 'change:3' })
end

return T
