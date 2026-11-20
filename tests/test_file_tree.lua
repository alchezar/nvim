-- nvim-tree as plugins/file-tree.lua sets it up. Cursorline lives in the tree
-- window only, the tree keeps no stray syntax, and no window keeps a local cwd.
-- Rows sort naturally with landmark notes, and the root follows the edited
-- project without a reload per focus.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local root -- fixture project the tree shows

-- A fresh dir, resolved. macOS temp paths sit behind a /private symlink.
local function new_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return vim.uv.fs_realpath(dir) or dir
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-web-devicons', 'nvim-tree.lua' } })
      child.o.lines, child.o.columns = 30, 120
      root = new_dir()
      vim.fn.mkdir(root .. '/src', 'p')
      vim.fn.writefile({ 'fn main() {}' }, root .. '/src/main.rs')
      vim.fn.writefile({ '# readme' }, root .. '/README.md')
      child.lua([[
        vim.cmd.cd(...)
        require('plugins.file-tree')
      ]], { root })
    end,
    post_once = child.stop,
  },
})

-- Open the tree, wait for its first render and go back to the editor window.
local function open_tree()
  child.lua([[
    local editor, done = vim.api.nvim_get_current_win(), false
    require('nvim-tree.api').events.subscribe('TreeRendered', function() done = true end)
    require('nvim-tree.api').tree.open()
    vim.wait(3000, function() return done end)
    vim.api.nvim_set_current_win(editor)
    -- The tree's cursorline is set a tick after its filetype lands.
    vim.wait(1000, function()
      local w = require('nvim-tree.api').tree.winid()
      return w ~= nil and vim.wo[w].cursorline
    end)
  ]])
end

-- cursorline per window, keyed by filetype ('' for the plain editor window).
local function cursorlines()
  return child.lua([[
    local out = {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      out[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = vim.wo[w].cursorline
    end
    return out
  ]])
end

-- Tree rows below the root line as `name [note]`, the note being the hint the
-- config draws at the end of the row.
local function rows()
  return child.lua([=[
    local buf = vim.fn.bufnr('NvimTree_*')
    local notes = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      local row, d = m[2], m[4]
      if d.virt_text_pos == 'eol' then
        notes[row] = (notes[row] or '') .. ' ' .. d.virt_text[1][1]
      end
    end
    local out = {}
    for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 1, -1, false)) do
      out[i] = l:match('(%S+)%s*$') .. (notes[i] or '')
    end
    return out
  ]=])
end

local function git_init(dir)
  local res = vim.system({ 'git', 'init', '-q' }, {
    cwd = dir,
    env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
  }):wait()
  assert(res.code == 0, res.stderr)
end

-- Put a git on the child's PATH that logs the args of each run to <bin>/log.
local function fake_git()
  local bin, git = new_dir(), vim.fn.exepath('git')
  vim.fn.writefile({
    '#!/bin/sh',
    'export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1',
    'echo "$*" >> "$(dirname "$0")/log"',
    'exec ' .. git .. ' "$@"',
  }, bin .. '/git')
  vim.fn.setfperm(bin .. '/git', 'rwxr-xr-x')
  child.lua([[vim.env.PATH = ... .. ':' .. vim.env.PATH]], { bin })
  return bin
end

-- The tree's root once it reaches `dir`, or wherever it stayed.
local function wait_root(dir)
  return child.lua([[
    local core, dir = require('nvim-tree.core'), ...
    vim.wait(1000, function() return core.get_cwd() == dir end, 10)
    return core.get_cwd()
  ]], { dir })
end

-- Git runs while :NvimTreeFocus (<leader>e) moves into the tree.
local function git_on_focus(bin)
  return child.lua([[
    local log = ... .. '/log'
    local function runs() return vim.uv.fs_stat(log) and vim.fn.readfile(log) or {} end
    local before = #runs()
    vim.cmd('NvimTreeFocus')
    return vim.list_slice(runs(), before + 1)
  ]], { bin })
end

-- A session started in src/ of the fixture project, made a repo, editing
-- src/main.rs. Returns the fake git's dir.
local function edit_from_subdir()
  local bin = fake_git()
  git_init(root)
  child.cmd('cd ' .. vim.fn.fnameescape(root .. '/src'))
  open_tree()
  child.cmd('edit ' .. vim.fn.fnameescape(root .. '/src/main.rs'))
  return bin
end

-- Before 2de74ef the first open showed no cursorline: BufWinEnter came before
-- the filetype was set.
T['first open lights only the tree'] = function()
  open_tree()
  eq(cursorlines(), { NvimTree = true, [''] = false })
end

-- Before a8e0f4a, a file opened from the tree as the only window landed in a
-- split of the tree window and inherited its cursorline.
T['a file opened from a lone tree has no cursorline'] = function()
  open_tree()
  child.lua([[
    local api = require('nvim-tree.api')
    api.tree.focus()
    vim.cmd('only')
    api.tree.find_file({ buf = vim.fn.bufadd(...), open = true, focus = true })
    api.node.open.edit()
    vim.wait(1000, function() return vim.bo.filetype == 'rust' end)
  ]], { root .. '/src/main.rs' })
  eq(cursorlines().rust, false)
end

-- Before 0f6f34f, a syntax left on a reused buffer lit up keyword-like names
-- such as the `mod` in mod.rs.
T['a re-render clears stray syntax from the tree'] = function()
  open_tree()
  local syntax = child.lua([[
    local api = require('nvim-tree.api')
    local buf = vim.fn.bufnr('NvimTree_*')
    vim.bo[buf].syntax = 'rust'
    local done = false
    api.events.subscribe('TreeRendered', function() done = true end)
    api.tree.reload()
    vim.wait(3000, function() return done end)
    return vim.bo[buf].syntax
  ]])
  eq(syntax, '')
end

-- Before b0d15e1, a plugin's window-local cwd made the tree see a new root on
-- every focus and reload in full.
T['a window-local cwd is dropped on the next window switch'] = function()
  child.cmd('vsplit')
  child.cmd('lcd ' .. vim.fn.fnameescape(root .. '/src'))
  child.cmd('wincmd p | wincmd p')
  eq(child.lua_get('vim.fn.haslocaldir()'), 0)
end

-- Before 2775046, names sorted as plain text (item10 before item2), and a
-- mod.rs or readme.md below subdirs gave no hint of which dir it was in.
T['a dir lists subdirs, landmarks naming it, then files in natural order'] = function()
  vim.fn.delete(root .. '/README.md')
  for _, f in ipairs({ 'item10.rs', 'item2.rs', 'item9.rs', 'mod.rs', 'readme.md', 'sub/mod.rs', 'sub/x.rs' }) do
    vim.fn.mkdir(vim.fs.dirname(root .. '/src/' .. f), 'p')
    vim.fn.writefile({}, root .. '/src/' .. f)
  end
  open_tree()
  child.lua([[
    local api, done = require('nvim-tree.api'), false
    api.events.subscribe('TreeRendered', function() done = true end)
    api.tree.expand_all()
    vim.wait(3000, function() return done end)
  ]])
  eq(rows(), {
    'src', 'sub', 'mod.rs', 'x.rs', 'readme.md [src]', 'mod.rs [src]',
    'item2.rs', 'item9.rs', 'item10.rs', 'main.rs',
  })
end

-- Between 1fd52e2 and b21666d, a session started in a project subdir kept the
-- subdir as the tree root.
T['a session started in a subdir re-roots the tree on the project'] = function()
  edit_from_subdir()
  eq(wait_root(root), root)
end

-- Before 1fd52e2, and again from b21666d to b4131b4, a session started in a
-- project subdir kept the tree window's cwd on the subdir, off the tree root,
-- so every focus reloaded the tree in full.
T['a session started in a subdir focuses the tree without a reload'] = function()
  local bin = edit_from_subdir()
  wait_root(root)
  eq(git_on_focus(bin), {})
end

-- From 1fd52e2 to b4131b4, a file of another project left the tree on the old
-- root. 1fd52e2 dropped the re-root, and the one b21666d added collided with
-- update_root (E367).
T['a file of another project re-roots the tree on it'] = function()
  local other = new_dir()
  vim.fn.writefile({}, other .. '/main.rs')
  git_init(other)
  open_tree()
  child.cmd('edit ' .. vim.fn.fnameescape(other .. '/main.rs'))
  eq(wait_root(other), other)
end

-- Before 1fd52e2, and again from b21666d to b4131b4, a file outside any
-- project re-rooted the tree on its dir but left the tree window's cwd
-- behind, so every focus reloaded the tree in full.
T['focusing the tree after a file outside any project runs no git'] = function()
  local bin = fake_git()
  git_init(root)
  local outside = new_dir()
  vim.fn.writefile({ 'notes' }, outside .. '/notes.md')
  open_tree()
  child.cmd('edit ' .. vim.fn.fnameescape(outside .. '/notes.md'))
  wait_root(outside)
  eq(git_on_focus(bin), {})
end

return T
