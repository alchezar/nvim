-- yazi and lazygit in a float from config/utils.lua, run as fakes on PATH
-- that log their args and cwd, then exit as the real tools do when closed.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local log

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.o.lines, child.o.columns = 30, 100
      local bin = vim.fn.tempname()
      vim.fn.mkdir(bin, 'p')
      log = vim.fn.tempname()
      -- yazi writes the file picked to its chooser file; $PICK names it.
      vim.fn.writefile({
        '#!/bin/sh',
        'for a; do case "$a" in --chooser-file=*) out="${a#--chooser-file=}";; *) dir="$a";; esac; done',
        'echo "yazi $dir" >> "$LOG"',
        '[ -n "$PICK" ] && echo "$PICK" > "$out"',
        'sleep 0.2',
      }, bin .. '/yazi')
      -- lazygit rewrites $EDIT on its way out, as a commit or checkout would.
      vim.fn.writefile({
        '#!/bin/sh',
        -- Asked for its config dir before the float opens; not a run.
        '[ "$1" = --print-config-dir ] && exit',
        'echo "lazygit $(pwd -P)" >> "$LOG"',
        '[ -n "$EDIT" ] && echo changed > "$EDIT"',
        'sleep 0.2',
      }, bin .. '/lazygit')
      vim.uv.fs_chmod(bin .. '/yazi', 493)
      vim.uv.fs_chmod(bin .. '/lazygit', 493)
      child.lua('vim.env.PATH = ... .. ":" .. vim.env.PATH; vim.env.LOG = select(2, ...)', { bin, log })
    end,
    post_once = child.stop,
  },
})

-- A file in its own resolved dir, open in the child.
local function open_file(lines)
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile(lines, dir .. '/a.txt')
  child.cmd('edit ' .. dir .. '/a.txt')
  return dir
end

-- Runs `fn` of utils; returns whether a float was up meanwhile, once the
-- tool has exited and its float is gone.
local function run(fn)
  return child.lua([[
    require('config.utils')[...]()
    local had = vim.api.nvim_win_get_config(0).relative ~= ''
    vim.wait(3000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= '' then return false end
      end
      return true
    end)
    vim.wait(50)
    return had
  ]], { fn })
end

T['yazi starts in the dir of the file and opens the file picked'] = function()
  local dir = open_file({ 'a' })
  vim.fn.writefile({ 'b' }, dir .. '/b.txt')
  child.lua('vim.env.PICK = ...', { dir .. '/b.txt' })
  local had = run('open_yazi')
  eq({ had, vim.fn.readfile(log), child.api.nvim_buf_get_name(0), #child.api.nvim_list_wins() },
    { true, { 'yazi ' .. dir }, dir .. '/b.txt', 1 })
end

T['yazi closed without a pick leaves the file as it was'] = function()
  local dir = open_file({ 'a' })
  eq({ run('open_yazi'), child.api.nvim_buf_get_name(0) }, { true, dir .. '/a.txt' })
end

T['lazygit runs in the dir of the file and the buffer catches its changes'] = function()
  local dir = open_file({ 'before' })
  child.lua('vim.env.EDIT = ...', { dir .. '/a.txt' })
  local had = run('open_lazygit')
  eq({ had, vim.fn.readfile(log), child.api.nvim_buf_get_lines(0, 0, -1, false) },
    { true, { 'lazygit ' .. dir }, { 'changed' } })
end

return T
