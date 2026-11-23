-- The buffers and recent files pickers from config/utils.lua: file names
-- tinted by their git state, rows led by the icon of their project.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'plenary.nvim', 'telescope.nvim' } })
      child.o.lines, child.o.columns = 30, 160
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

-- A repo with a clean, a modified, a staged new and an untracked file, all
-- open in the child; `icons` maps project roots to icons for config.projects.
local function repo(icons)
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  vim.fn.mkdir(dir, 'p')
  git(dir, 'init', '-q')
  vim.fn.writefile({ 'a' }, dir .. '/clean.rs')
  vim.fn.writefile({ 'a' }, dir .. '/changed.rs')
  git(dir, 'add', '.')
  git(dir, 'commit', '-q', '-m', 'base')
  vim.fn.writefile({ 'b' }, dir .. '/changed.rs')
  vim.fn.writefile({ 'a' }, dir .. '/added.rs')
  git(dir, 'add', 'added.rs')
  vim.fn.writefile({ 'a' }, dir .. '/loose.rs')
  local groups = { work = {} }
  for root, icon in pairs(icons or {}) do
    table.insert(groups.work, { path = root:gsub('^%.', dir), icon = icon })
  end
  child.lua([[
    local dir, groups = ...
    package.loaded['config.projects'] = groups
    require('plugins.telescope_setup')
    vim.cmd.cd(dir)
    for _, f in ipairs({ 'clean.rs', 'changed.rs', 'added.rs', 'loose.rs' }) do vim.cmd.edit(f) end
  ]], { dir, groups })
  return dir
end

-- Picker rows as `text`, each with the highlight of its file name.
local function rows(open)
  return child.lua([[
    loadstring(...)()
    local buf
    vim.wait(2000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.bo[b].filetype == 'TelescopeResults' then
          buf = b
          return #vim.tbl_filter(function(r) return r ~= '' end, vim.api.nvim_buf_get_lines(b, 0, -1, false)) > 0
        end
      end
    end)
    local out = {}
    for row, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if text ~= '' then
        local name_hl
        local col = text:find('%a+%.rs')
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
          if col and m[3] == col - 1 and m[4].hl_group then name_hl = m[4].hl_group end
        end
        out[#out + 1] = { text, name_hl }
      end
    end
    return out
  ]], { open })
end

-- Row text and file-name highlight of `rows` keyed by file name.
local function by_name(list)
  local out = {}
  for _, r in ipairs(list) do out[r[1]:match('(%a+)%.rs')] = { r[1], r[2] } end
  return out
end

T['a buffer name is tinted by its git state'] = function()
  repo()
  local got = by_name(rows([[require('config.utils').buffers()]]))
  eq({ got.clean[2], got.changed[2], got.added[2], got.loose[2] },
    { nil, 'TelescopeBufferGitDirty', 'TelescopeBufferGitNew', 'TelescopeBufferGitUntracked' })
end

T['a buffer row carries the icon of its project, names stay aligned'] = function()
  repo({ ['.'] = 'W' })
  local other = vim.fn.tempname() .. '/outside.rs'
  vim.fn.mkdir(vim.fs.dirname(other), 'p')
  vim.fn.writefile({ 'a' }, other)
  child.cmd('edit ' .. other)
  local got = by_name(rows([[require('config.utils').buffers()]]))
  local inside, outside = got.clean[1], got.outside[1]
  eq({ inside:find(' W ') ~= nil, outside:find(' W ') ~= nil, (outside:find('outside')) },
    { true, false, (inside:find('clean')) })
end

T['a recent file shows its project icon, then the mirrored path'] = function()
  local dir = repo({ ['.'] = 'W' })
  vim.fn.mkdir(dir .. '/src', 'p')
  vim.fn.writefile({ 'a' }, dir .. '/src/deep.rs')
  child.lua('vim.v.oldfiles = ...', { { dir .. '/src/deep.rs' } })
  child.cmd('enew')
  local got = by_name(rows([[require('telescope.builtin').oldfiles()]]))
  eq(vim.trim((got.deep[1]:gsub('^>', ''))), 'W  deep.rs\\src')
end

return T
