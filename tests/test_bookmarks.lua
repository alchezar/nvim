-- bookmarks: m{group} toggles a sign on the line, saved marks find their line
-- again by its text, and the signs keep their color across a theme reload.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local data -- per-case data dir, so the real bookmarks.json is never touched

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      data = vim.fn.tempname()
      child.lua('vim.env.XDG_DATA_HOME = ...', { data })
    end,
    post_once = child.stop,
  },
})

local function load() child.lua([[require('custom.bookmarks')]]) end

local function edit(lines)
  local file = vim.fn.tempname() .. '.txt'
  vim.fn.writefile(lines, file)
  child.cmd('edit ' .. file)
  return file
end

-- Signs as `row:text:group` (1-based rows).
local function signs()
  return child.lua([[
    local ns = vim.api.nvim_get_namespaces().user_bookmarks
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      out[#out + 1] = (m[2] + 1) .. ':' .. vim.trim(m[4].sign_text) .. ':' .. m[4].sign_hl_group
    end
    return out
  ]])
end

T['m1 toggles a numbered sign on the line'] = function()
  load()
  edit({ 'alpha', 'beta', 'gamma' })
  child.type_keys('2G', 'm1')
  eq(signs(), { '2:1:UserBookmark1' })
  child.type_keys('m1')
  eq(signs(), {})
end

T['a saved mark follows its text to a new line'] = function()
  local file = vim.uv.fs_realpath(edit({ 'new first line', 'alpha', 'beta' }))
  vim.fn.mkdir(data .. '/nvim', 'p')
  vim.fn.writefile({ vim.json.encode({ [file] = { { group = 2, line = 2, text = 'beta' } } }) },
    data .. '/nvim/bookmarks.json')
  load()
  eq(signs(), { '3:2:UserBookmark2' })
end

-- Before a4a3187, :colorscheme clears every group, and the signs went grey.
T['signs keep their color after a colorscheme change'] = function()
  load()
  child.cmd('colorscheme default')
  eq(child.lua_get([[vim.api.nvim_get_hl(0, { name = 'UserBookmark1' }).fg ~= nil]]), true)
end

return T
