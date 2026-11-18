-- utils.auto_cd_to_project_root keeps one global cwd on the project of the
-- file being edited, which nvim-tree's root follows.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

-- A fresh dir, resolved. macOS temp paths sit behind a /private symlink.
local function new_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return vim.uv.fs_realpath(dir) or dir
end

-- A project with a .git marker and a file in a subdir; returns both paths.
local function project()
  local root = new_dir()
  vim.fn.mkdir(root .. '/.git', 'p')
  vim.fn.mkdir(root .. '/src', 'p')
  vim.fn.writefile({}, root .. '/src/main.rs')
  return root, root .. '/src/main.rs'
end

local function cd_for(file)
  child.cmd('edit ' .. file)
  child.lua([[require('config.utils').auto_cd_to_project_root(0)]])
  return child.lua_get('vim.fn.getcwd(-1, -1)')
end

T['cd goes to the project root, not the file dir'] = function()
  local root, file = project()
  eq(cd_for(file), root)
end

T['a file outside any project uses its own dir'] = function()
  local dir = new_dir()
  vim.fn.writefile({}, dir .. '/notes.txt')
  eq(cd_for(dir .. '/notes.txt'), dir)
end

-- Before 98eb8f8, a window-local cwd already on the root (startify's lcd)
-- read as "already there", and the global cwd stayed on the old project.
T['a local cwd on the root still moves the global one'] = function()
  local root, file = project()
  child.cmd('edit ' .. file)
  child.cmd('lcd ' .. root)
  eq(cd_for(file), root)
end

return T
