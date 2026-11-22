-- Telescope git status from config/utils.lua, with the diff preview of
-- custom/git_diff_preview.lua: bare source keeping its syntax, add/delete as
-- line backgrounds, hunk headers as virtual text.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true, plugins = { 'plenary.nvim', 'telescope.nvim' } })
      child.o.lines, child.o.columns = 40, 200
      child.lua([[require('plugins.telescope_setup')]])
    end,
    post_once = child.stop,
  },
})

local function git(dir, args)
  local res = vim.system(vim.list_extend({ 'git', '-c', 'user.name=t', '-c', 'user.email=t@t' }, args), {
    cwd = dir,
    env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
  }):wait()
  assert(res.code == 0, res.stderr)
end

-- A repo where `a.rs` and `b.rs` changed since the commit and `new.rs` is
-- untracked; `b.rs` is the current buffer.
local function repo()
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('^(.*)/')))
  dir = dir .. '/repo' .. math.random(1e9)
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'fn a() {', '    old();', '}' }, dir .. '/a.rs')
  vim.fn.writefile({ 'fn b() {}' }, dir .. '/b.rs')
  git(dir, { 'init', '-q' })
  git(dir, { 'add', '.' })
  git(dir, { 'commit', '-q', '-m', 'c' })
  vim.fn.writefile({ 'fn a() {', '    new();', '}' }, dir .. '/a.rs')
  vim.fn.writefile({ 'fn b() { 1 }' }, dir .. '/b.rs')
  vim.fn.writefile({ 'fn n() {}' }, dir .. '/new.rs')
  child.lua('vim.cmd.cd(...)', { dir })
  child.cmd('edit b.rs')
  return dir
end

-- Opens the picker, selects the row for `name` when given, and returns the
-- selected file with what its preview shows.
local function preview(name)
  return child.lua([[
    local name = ...
    require('config.utils').git_status()
    local picker
    vim.wait(3000, function()
      local state = require('telescope.actions.state')
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[b].filetype == 'TelescopePrompt' then picker = state.get_current_picker(b) end
      end
      return picker and picker.manager and picker.manager:num_results() == 3 and picker:get_selection() ~= nil
    end)
    if name then
      for i = 1, picker.manager:num_results() do
        if vim.fs.basename(picker.manager:get_entry(i).path) == name then
          picker:set_selection(picker:get_row(i))
        end
      end
    end
    local entry = picker:get_selection()
    local buf = picker.previewer.state and picker.previewer.state.bufnr
    vim.wait(3000, function()
      buf = picker.previewer.state and picker.previewer.state.bufnr
      return buf and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= ''
        or (buf and #vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}) > 0)
    end)
    vim.wait(200)
    local ns = vim.api.nvim_get_namespaces()['kinder.git_diff_preview']
    local marks = {}
    for _, m in ipairs(ns and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) or {}) do
      marks[#marks + 1] = (m[2] + 1) .. ' ' .. (m[4].line_hl_group or m[4].virt_text[1][1])
    end
    return {
      file = vim.fs.basename(entry.path),
      lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
      marks = marks,
      syntax = vim.treesitter.highlighter.active[buf] ~= nil,
    }
  ]], { name })
end

T['it opens on the current file'] = function()
  repo()
  eq(preview().file, 'b.rs')
end

-- Before 1a50669, the output's final newline added a blank line after the diff.
T['a diff previews as source with tinted lines and the hunk header'] = function()
  repo()
  local got = preview('a.rs')
  eq(got, {
    file = 'a.rs',
    lines = { '', 'fn a() {', '    old();', '    new();', '}' },
    marks = { '1 @@ -1,3 +1,3 @@', '3 GitDiffPreviewDelete', '4 GitDiffPreviewAdd' },
    syntax = true,
  })
end

T['an untracked file previews as itself'] = function()
  repo()
  eq(preview('new.rs').lines, { 'fn n() {}' })
end

return T
