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

-- f9bf395: mod.rs was skipped outright, so a feature that is a dir with its
-- own mod.rs vanished from the tree.
T['dir feature with mod.rs is kept'] = function()
  eq(rows({ 'api/orders.rs', 'db/orders.rs', 'api/sync/mod.rs', 'db/sync/mod.rs' }),
    { 'orders', 'api.rs', 'db.rs', 'sync', 'api.rs', 'db.rs' })
end

return T
