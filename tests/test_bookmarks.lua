-- bookmarks: m{group} toggles a sign on the line, saved marks find their line
-- again by its text, and the signs keep their color across a theme reload.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local data -- per-case data dir, so the real bookmarks.json is never touched

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'plenary.nvim', 'telescope.nvim' } })
      child.o.lines, child.o.columns = 30, 160
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

-- A project (a dir with .git) holding `files` as name -> lines; returns its
-- resolved path. `store` seeds bookmarks.json as path -> marks.
local function project(files)
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  vim.fn.mkdir(dir .. '/.git', 'p')
  for name, lines in pairs(files) do vim.fn.writefile(lines, dir .. '/' .. name) end
  return dir
end

local function seed(store)
  vim.fn.mkdir(data .. '/nvim', 'p')
  vim.fn.writefile({ vim.json.encode(store) }, data .. '/nvim/bookmarks.json')
end

local function mark(group, line, text) return { group = group, line = line, text = text } end

-- `file:line` of the cursor, the file by its name only.
local function here()
  return vim.fn.fnamemodify(child.api.nvim_buf_get_name(0), ':t') .. ':' .. child.api.nvim_win_get_cursor(0)[1]
end

T['a jump cycles through its group over the files of the project'] = function()
  local dir = project({ ['a.txt'] = { 'one', 'two' }, ['b.txt'] = { 'x', 'y', 'z' } })
  local other = project({ ['c.txt'] = { 'far' } })
  seed({
    [dir .. '/a.txt'] = { mark(1, 2, 'two') },
    [dir .. '/b.txt'] = { mark(1, 1, 'x'), mark(2, 2, 'y'), mark(1, 3, 'z') },
    [other .. '/c.txt'] = { mark(1, 1, 'far') },
  })
  load()
  child.cmd('edit ' .. dir .. '/a.txt')
  local seen = {}
  for _ = 1, 4 do
    child.type_keys('`1')
    seen[#seen + 1] = here()
  end
  eq(seen, { 'a.txt:2', 'b.txt:1', 'b.txt:3', 'a.txt:2' })
end

T['a letter mark answers both quote jumps'] = function()
  load()
  edit({ 'alpha', 'beta', 'gamma' })
  child.type_keys('2G', 'ma', 'mB', 'G')
  child.type_keys("'a")
  local by_quote = child.api.nvim_win_get_cursor(0)[1]
  child.type_keys('G', '`B')
  eq({ by_quote, child.api.nvim_win_get_cursor(0)[1], #signs() }, { 2, 2, 2 })
end

T['dm drops one group from the buffer and keeps the rest'] = function()
  load()
  edit({ 'alpha', 'beta', 'gamma' })
  child.type_keys('1G', 'm1', '2G', 'm2', '3G', 'm1', 'dm1')
  eq(signs(), { '2:2:UserBookmark2' })
end

T['alt-m sets a plain mark, or clears every mark on the line'] = function()
  load()
  edit({ 'alpha', 'beta' })
  child.type_keys('<M-m>')
  local plain = signs()
  child.type_keys('m3', '<M-m>')
  eq({ #plain, plain[1]:match('UserBookmarkPlain$'), signs() }, { 1, 'UserBookmarkPlain', {} })
end

-- Rows of the bookmark picker once it has any, trimmed.
local function picker_rows()
  return child.lua([[
    local out
    vim.wait(2000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.bo[b].filetype == 'TelescopeResults' then
          out = vim.tbl_filter(function(r) return r ~= '' end, vim.api.nvim_buf_get_lines(b, 0, -1, false))
          return #out > 0
        end
      end
    end)
    return vim.tbl_map(function(r) return vim.trim((r:gsub('^>', ''))) end, out or {})
  ]])
end

local function close_picker()
  child.lua([[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'TelescopePrompt' then
        require('telescope.actions').close(vim.api.nvim_win_get_buf(w))
        return
      end
    end
  ]])
end

T['the list shows the project, the capital list every project'] = function()
  local dir = project({ ['a.txt'] = { 'one', 'two' } })
  local other = project({ ['c.txt'] = { 'far' } })
  seed({ [dir .. '/a.txt'] = { mark(1, 2, 'two') }, [other .. '/c.txt'] = { mark('k', 1, 'far') } })
  load()
  child.lua([[require('plugins.telescope_setup')]])
  child.cmd('cd ' .. dir)
  child.cmd('edit a.txt')
  child.type_keys('\\m')
  local project_rows = picker_rows()
  close_picker()
  child.type_keys('\\M')
  local all = picker_rows()
  eq({ project_rows, #all, all[2]:match('c%.txt  1  far$') ~= nil },
    { { '1  a.txt  2  two' }, 2, true })
end

T['dd in the list deletes a bookmark of a file that is not open'] = function()
  local dir = project({ ['a.txt'] = { 'one' }, ['b.txt'] = { 'x', 'y' } })
  seed({ [dir .. '/b.txt'] = { mark(1, 1, 'x'), mark(2, 2, 'y') } })
  load()
  child.lua([[require('plugins.telescope_setup')]])
  child.cmd('cd ' .. dir)
  child.cmd('edit a.txt')
  child.type_keys('\\m')
  picker_rows()
  child.cmd('stopinsert')
  child.type_keys('dd')
  local left = picker_rows()
  child.lua('vim.wait(100)')
  local stored = vim.json.decode(table.concat(vim.fn.readfile(data .. '/nvim/bookmarks.json'), '\n'))
  eq({ left, stored[dir .. '/b.txt'] }, { { '2  b.txt  2  y' }, { mark(2, 2, 'y') } })
end

return T
