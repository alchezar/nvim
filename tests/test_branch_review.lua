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

-- Before 9e86e1f, a renamed file got no base, as gitsigns looked its absolute
-- path up in a map keyed by repo paths. Today's gitsigns resolves it itself,
-- so this fails only with the gitsigns locked back then.
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

-- A repo on branch `feat`, forked from main. Its first commit changes
-- src/b.txt, its second a.txt, and c.txt is untracked. Returns the dir and
-- the hash of the first commit.
local function branch()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp .. '/src', 'p')
  local dir = vim.uv.fs_realpath(tmp) or tmp
  git(dir, 'init', '-q', '-b', 'main')
  vim.fn.writefile({ 'a' }, dir .. '/a.txt')
  vim.fn.writefile({ 'b' }, dir .. '/src/b.txt')
  git(dir, 'add', '.')
  git(dir, 'commit', '-q', '-m', 'base')
  git(dir, 'checkout', '-q', '-b', 'feat')
  vim.fn.writefile({ 'B' }, dir .. '/src/b.txt')
  git(dir, 'commit', '-q', '-am', 'one')
  local first = vim.trim(vim.system({ 'git', 'rev-parse', 'HEAD' }, { cwd = dir }):wait().stdout)
  vim.fn.writefile({ 'A' }, dir .. '/a.txt')
  git(dir, 'commit', '-q', '-am', 'two')
  vim.fn.writefile({ 'c' }, dir .. '/c.txt')
  child.lua('vim.cmd.cd(...)', { dir })
  return dir, first
end

-- Paths under review relative to `dir`, sorted; {} when review is off.
local function reviewed(dir, base)
  return child.lua([[
    local dir, base = ...
    local br = require('custom.branch_review')
    br.toggle(base ~= vim.NIL and base or nil)
    local out = {}
    for path in pairs(br.active and br.changed or {}) do out[#out + 1] = path:sub(#dir + 2) end
    table.sort(out)
    return out
  ]], { dir, base or vim.NIL })
end

T['with no base it reviews everything since main'] = function()
  local dir = branch()
  eq(reviewed(dir), { 'a.txt', 'c.txt', 'src/b.txt' })
end

T['a count of commits and a hash both set how far back to look'] = function()
  local dir, first = branch()
  child.lua([[vim.ui.input = function(_, done) done(_G.answer) end]])
  local function asked(answer)
    child.lua('_G.answer = ...; require("config.utils").branch_review_toggle()', { answer })
    return child.lua([[
      local dir, br, out = ..., require('custom.branch_review'), {}
      for path in pairs(br.changed) do out[#out + 1] = path:sub(#dir + 2) end
      table.sort(out)
      return out
    ]], { dir })
  end
  eq({ asked('1'), asked(first) }, { { 'a.txt', 'c.txt' }, { 'a.txt', 'c.txt', 'src/b.txt' } })
end

-- Highlights the review puts on the tree, as `name group`.
local function tree_marks()
  return child.lua([[
    local ns = vim.api.nvim_get_namespaces().branch_review_tree
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'NvimTree' then
        local out = {}
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })) do
          local text = vim.api.nvim_buf_get_text(b, m[2], m[3], m[2], m[4].end_col, {})[1]
          out[#out + 1] = text .. ' ' .. m[4].hl_group
        end
        table.sort(out)
        return out
      end
    end
  ]])
end

T['the tree tints changed files and the folders above them, until it ends'] = function()
  local dir = branch()
  child.lua([[
    require('nvim-tree').setup({})
    require('nvim-tree.api').tree.open()
    require('nvim-tree.api').tree.expand_all()
  ]])
  reviewed(dir)
  child.lua('vim.wait(200)')
  local on = tree_marks()
  reviewed(dir)
  child.lua('vim.wait(200)')
  eq({ on, tree_marks() }, {
    { 'a.txt BranchReviewFile', 'b.txt BranchReviewFile', 'c.txt BranchReviewFile', 'src BranchReviewFolder' },
    {},
  })
end

return T
