-- nvim-tree as plugins/file-tree.lua sets it up. Cursorline lives in the tree
-- window only, the tree keeps no stray syntax, and no window keeps a local cwd.
-- Rows sort naturally with landmark notes.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local root -- fixture project the tree shows

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-web-devicons', 'nvim-tree.lua' } })
      child.o.lines, child.o.columns = 30, 120
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp .. '/src', 'p')
      root = vim.uv.fs_realpath(tmp) or tmp
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

-- Open the tree without focus and wait for its first render.
local function open_tree()
  child.lua([[
    local done = false
    require('nvim-tree.api').events.subscribe('TreeRendered', function() done = true end)
    require('nvim-tree.api').tree.open({ focus = false })
    vim.wait(3000, function() return done end)
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

return T
