-- feature_tree transposes src/<layer>/<feature>.rs into feature > layer rows.
-- Checked by the panel text, glyphs stripped, every folder unfolded.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.o.lines, child.o.columns = 40, 120
    end,
    post_once = child.stop,
  },
})

-- Panel rows for a crate holding `files` (paths under src/), opened from the
-- first file. A plain split stands in for nvim-tree, which the panel splits.
local function rows(files)
  local root = vim.fn.tempname() .. '/shop'
  vim.fn.mkdir(root .. '/src', 'p')
  vim.fn.writefile({}, root .. '/Cargo.toml')
  for _, f in ipairs(files) do
    vim.fn.mkdir(vim.fs.dirname(root .. '/src/' .. f), 'p')
    vim.fn.writefile({}, root .. '/src/' .. f)
  end
  child.cmd('edit ' .. root .. '/src/' .. files[1])
  return child.lua([[
    vim.cmd('topleft vnew | setlocal filetype=NvimTree | wincmd l')
    require('custom.feature_tree').open()
    vim.api.nvim_feedkeys('zR', 'x', false)
    local out = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      l = vim.trim((l:gsub('[\128-\255]+', '')))
      if l ~= '' then out[#out + 1] = l end
    end
    return out
  ]])
end

T['groups each feature across layers'] = function()
  eq(rows({ 'api/orders.rs', 'db/orders.rs', 'api/mod.rs', 'bin/tool.rs' }),
    { 'orders', 'api.rs', 'db.rs' })
end

-- Before f9bf395, mod.rs was skipped outright, so a feature that is a dir with
-- its own mod.rs vanished from the tree.
T['dir feature with mod.rs is kept'] = function()
  eq(rows({ 'api/orders.rs', 'db/orders.rs', 'api/sync/mod.rs', 'db/sync/mod.rs' }),
    { 'orders', 'api.rs', 'db.rs', 'sync', 'api.rs', 'db.rs' })
end

local function git(dir, ...)
  local res = vim.system({ 'git', '-c', 'user.name=t', '-c', 'user.email=t@t', ... }, {
    cwd = dir,
    env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
  }):wait()
  assert(res.code == 0, res.stderr)
end

-- A crate holding `files` (paths under src/), each opening with a `//!` doc
-- naming it. With `changed`, it is a repo where those files differ from HEAD.
local function crate(files, changed)
  local root = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t') .. '/shop'
  vim.fn.mkdir(root .. '/src', 'p')
  vim.fn.writefile({}, root .. '/Cargo.toml')
  for _, f in ipairs(files) do
    vim.fn.mkdir(vim.fs.dirname(root .. '/src/' .. f), 'p')
    vim.fn.writefile({ '//! Doc of ' .. f .. '.' }, root .. '/src/' .. f)
  end
  if changed then
    git(root, 'init', '-q')
    git(root, 'add', '.')
    git(root, 'commit', '-q', '-m', 'base')
    for _, f in ipairs(changed) do vim.fn.writefile({ '//! Changed.' }, root .. '/src/' .. f) end
  end
  return root
end

-- Opens the panel from `file` of `root`, focus left in the panel.
local function open_panel(root, file)
  child.cmd('edit ' .. root .. '/src/' .. file)
  child.lua([[
    vim.cmd('topleft vnew | setlocal filetype=NvimTree | wincmd l')
    require('custom.feature_tree').open()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'FeatureTree' then vim.api.nvim_set_current_win(w) end
    end
  ]])
end

-- Panel rows, glyphs stripped; {} once the panel is gone.
local function panel_rows()
  return child.lua([[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'FeatureTree' then
        local out = {}
        for _, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
          l = vim.trim((l:gsub('[\128-\255]+', '')))
          if l ~= '' then out[#out + 1] = l end
        end
        return out
      end
    end
    return {}
  ]])
end

local function to_row(text)
  for i, r in ipairs(panel_rows()) do
    if r == text then return child.api.nvim_win_set_cursor(0, { i, 0 }) end
  end
  error('no row ' .. text)
end

local FILES = { 'api/orders.rs', 'db/orders.rs', 'api/users.rs', 'db/users.rs' }

T['enter opens the file in the editor and keeps the panel'] = function()
  local root = crate(FILES)
  open_panel(root, 'api/orders.rs')
  child.type_keys('zR')
  to_row('users')
  child.type_keys('j', '<CR>')
  eq({ child.api.nvim_buf_get_name(0), #panel_rows() > 0 }, { root .. '/src/api/users.rs', true })
end

T['tab folds a feature, zM folds all and zR opens all'] = function()
  open_panel(crate(FILES), 'api/orders.rs')
  child.type_keys('zR')
  to_row('orders')
  child.type_keys('<Tab>')
  local one = panel_rows()
  child.type_keys('zM')
  local all = panel_rows()
  child.type_keys('zR')
  eq({ one, all, panel_rows() }, {
    { 'orders', 'users',  'api.rs', 'db.rs' },
    { 'orders', 'users' },
    { 'orders', 'api.rs', 'db.rs',  'users', 'api.rs', 'db.rs' },
  })
end

T['q closes the panel'] = function()
  open_panel(crate(FILES), 'api/orders.rs')
  child.type_keys('q')
  eq(panel_rows(), {})
end

-- The feature of the file open stays unfolded too, to show where it sits.
T['only features with changes start unfolded'] = function()
  local files = vim.list_extend({ 'api/carts.rs', 'db/carts.rs' }, FILES)
  open_panel(crate(files, { 'db/users.rs' }), 'api/orders.rs')
  eq(panel_rows(), { 'carts', 'orders', 'api.rs', 'db.rs', 'users', 'api.rs', 'db.rs' })
end

-- A feature in one layer only joins the `root` group as `layer/file`.
T['a file saved into a layer shows up in the panel'] = function()
  local root = crate(FILES)
  open_panel(root, 'api/orders.rs')
  child.type_keys('zR')
  child.cmd('wincmd p')
  child.cmd('edit ' .. root .. '/src/api/carts.rs')
  child.cmd('write')
  local before = vim.tbl_contains(panel_rows(), 'api/carts.rs')
  child.lua('vim.wait(500)')
  eq({ before, vim.tbl_contains(panel_rows(), 'api/carts.rs') }, { false, true })
end

T['gh shows the module doc of the file'] = function()
  open_panel(crate(FILES), 'api/orders.rs')
  child.type_keys('zR')
  to_row('orders')
  child.type_keys('j', 'gh')
  eq(child.lua([[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= '' then
        return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
      end
    end
  ]]), { 'Doc of api/orders.rs.' })
end

T['a single click opens a file'] = function()
  local root = crate(FILES)
  open_panel(root, 'api/orders.rs')
  child.type_keys('zR')
  to_row('users')
  local pos = child.lua([[
    local w = vim.api.nvim_get_current_win()
    local row, col = unpack(vim.api.nvim_win_get_position(w))
    return { row + vim.api.nvim_win_get_cursor(w)[1], col + 6 }
  ]])
  child.api.nvim_input_mouse('left', 'press', '', 0, pos[1], pos[2])
  child.api.nvim_input_mouse('left', 'release', '', 0, pos[1], pos[2])
  child.lua('vim.wait(50)')
  eq(child.api.nvim_buf_get_name(0), root .. '/src/api/users.rs')
end

return T
