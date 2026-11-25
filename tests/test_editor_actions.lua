-- Editor actions from config/utils.lua, driven through their keys in
-- config/keys.lua where they have one.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local home

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'plenary.nvim', 'telescope.nvim', 'translate.nvim' } })
      child.o.lines, child.o.columns = 30, 100
      -- A home with the speaker script, read when utils loads.
      home = vim.fn.tempname()
      vim.fn.mkdir(home .. '/.hammerspoon', 'p')
      vim.fn.writefile({}, home .. '/.hammerspoon/speak.js')
      child.lua([[
        vim.env.HOME = ...
        _G.notes, _G.clip = {}, {}
        vim.notify = function(msg) table.insert(_G.notes, msg) end
        local function copy(lines) _G.clip = lines end
        local function paste() return _G.clip end
        vim.g.clipboard = { name = 'test', copy = { ['+'] = copy, ['*'] = copy }, paste = { ['+'] = paste, ['*'] = paste } }
        require('config.keys')
      ]], { home })
    end,
    post_once = child.stop,
  },
})

local function file(lines)
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile(lines, path)
  return assert(vim.uv.fs_realpath(path))
end

local function open_clipboard(text)
  child.lua([[vim.fn.setreg('+', ...); require('config.utils').open_clipboard_path()]], { text })
  return { vim.fn.fnamemodify(child.api.nvim_buf_get_name(0), ':t'), child.api.nvim_win_get_cursor(0) }
end

T['a path from the clipboard opens at its line and column'] = function()
  local path = file({ 'one', 'two', 'three' })
  local name = vim.fn.fnamemodify(path, ':t')
  eq({ open_clipboard(path .. ':3:2'), open_clipboard(path .. ':2'), open_clipboard('  ' .. path .. '  ') },
    { { name, { 3, 1 } }, { name, { 2, 0 } }, { name, { 2, 0 } } })
end

T['a clipboard path that is no file only warns'] = function()
  child.lua([[vim.fn.setreg('+', '/no/such/file:3'); require('config.utils').open_clipboard_path()]])
  eq({ child.api.nvim_buf_get_name(0), child.lua_get('_G.notes') }, { '', { 'File not found: /no/such/file' } })
end

T['reload reads the file again and keeps the cursor'] = function()
  local path = file({ 'one', 'two', 'three' })
  child.cmd('edit ' .. path)
  child.api.nvim_win_set_cursor(0, { 2, 1 })
  vim.fn.writefile({ 'ONE', 'TWO', 'THREE' }, path)
  child.lua([[require('config.utils').reload_buf()]])
  eq({
    child.api.nvim_buf_get_lines(0, 0, -1, false),
    child.api.nvim_win_get_cursor(0),
    #vim.tbl_filter(function(b) return child.api.nvim_buf_is_loaded(b) end, child.api.nvim_list_bufs()),
  }, { { 'ONE', 'TWO', 'THREE' }, { 2, 1 }, 1 })
end

T['reload refuses a buffer with unsaved changes'] = function()
  local path = file({ 'one' })
  child.cmd('edit ' .. path)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'mine' })
  vim.fn.writefile({ 'theirs' }, path)
  child.lua([[require('config.utils').reload_buf()]])
  eq({ child.api.nvim_buf_get_lines(0, 0, -1, false), child.lua_get('_G.notes') },
    { { 'mine' }, { 'Buffer has unsaved changes - save first' } })
end

T['focus jumps into a float and back, skipping unfocusable ones'] = function()
  local main = child.api.nvim_get_current_win()
  local float = child.lua([[
    local function open(focusable)
      return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false,
        { relative = 'editor', row = 1, col = 1, width = 10, height = 2, focusable = focusable })
    end
    open(false)
    return open(true)
  ]])
  child.lua([[require('config.utils').focus_floating()]])
  local into = child.api.nvim_get_current_win()
  child.lua([[require('config.utils').focus_floating()]])
  eq({ into, child.api.nvim_get_current_win() }, { float, main })
end

T['star on a selection searches it literally'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'a.b', 'axb', 'a.b' })
  child.type_keys('gg', 'v', 'll', '*')
  eq({ child.fn.getreg('/'), child.api.nvim_win_get_cursor(0) }, { '\\Va.b', { 3, 0 } })
end

T['speaking a selection joins its paragraphs, a second press stops it'] = function()
  child.lua([[
    _G.spoken, _G.killed = {}, 0
    vim.system = function(cmd)
      table.insert(_G.spoken, cmd)
      return { kill = function() _G.killed = _G.killed + 1 end }
    end
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', '  two', '', 'three' })
  child.type_keys('gg', 'V', 'G')
  child.lua([[require('config.utils').speak_selection()]])
  local mode = child.api.nvim_get_mode().mode
  child.lua([[require('config.utils').speak_selection()]])
  local spoken = child.lua_get('_G.spoken')
  eq({ #spoken, spoken[1][1], spoken[1][#spoken[1]], mode, child.lua_get('_G.killed') },
    { 1, 'osascript', 'one two\nthree', 'n', 1 })
end

return T
