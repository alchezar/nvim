-- axum_routes.collect: which `METHOD /path` endpoints a Rust file yields,
-- from utoipa attrs and the route comments over handlers.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'plenary.nvim', 'telescope.nvim' } })
      child.o.lines, child.o.columns = 30, 200
    end,
    post_once = child.stop,
  },
})

-- Endpoints of a file holding `lines`, as `METHOD path handler`.
local function endpoints(lines)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile(lines, dir .. '/routes.rs')
  -- Also cd there. Older code ignored the file and scanned the project.
  return child.lua([[
    local dir = ...
    vim.cmd.cd(dir)
    local out = {}
    for _, e in ipairs(require('custom.axum_routes').collect(dir .. '/routes.rs')) do
      out[#out + 1] = ('%s %s %s'):format(e.method, e.path, e.handler)
    end
    return out
  ]], { dir })
end

local function utoipa(method, path, fn)
  return { '#[utoipa::path(', '    ' .. method .. ',', '    path = "' .. path .. '",', ')]',
    'pub async fn ' .. fn .. '() {}' }
end

local function with(head, tail)
  local out = vim.list_extend({}, head)
  return vim.list_extend(out, tail)
end

T['route comment gives the full path'] = function()
  eq(endpoints(with({ '// GET /api/users' }, utoipa('get', '/users', 'list_users'))),
    { 'GET /api/users list_users' })
end

T['utoipa attr alone gives the relative path'] = function()
  eq(endpoints(utoipa('post', '/items', 'create_item')), { 'POST /items create_item' })
end

-- Before 7d08bd1, any comment naming a route counted, even over a type.
T['route comment over a type is ignored'] = function()
  eq(endpoints({ '// GET /api/users', 'pub struct UsersPage {}' }), {})
end

-- Before 5dc131e, prose naming another endpoint became a ghost entry.
T['route mentioned in prose is ignored'] = function()
  local lines = with({ '/// Same data as GET /api/legacy, newer shape.' },
    utoipa('get', '/users', 'list_users'))
  eq(endpoints(lines), { 'GET /users list_users' })
end

-- Before f3d565e, a documented query string broke the match with utoipa's path.
T['query string in the comment still matches'] = function()
  eq(endpoints(with({ '// GET /api/users?page=1' }, utoipa('get', '/users', 'list_users'))),
    { 'GET /api/users?page=1 list_users' })
end

T['bare handler needs a banner that is only the route'] = function()
  eq(endpoints({ '// POST /api/login', 'pub async fn login() {}' }), { 'POST /api/login login' })
  eq(endpoints({ '// see POST /api/login for details', 'fn helper() {}' }), {})
end

-- A file with two documented endpoints, open in the child with the cursor on
-- `line`, its file picker started; returns the file.
local function file_picker(line)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/src', 'p')
  dir = assert(vim.uv.fs_realpath(dir))
  local file = dir .. '/src/routes.rs'
  vim.fn.writefile(with(with({ '/// Lists users.' }, utoipa('get', '/api/v1/users', 'list_users')),
    with({ '', '/// One user.' }, utoipa('delete', '/api/v1/users/{id}', 'drop_user'))), file)
  child.lua([[
    local dir, file, line = ...
    require('plugins.telescope_setup')
    require('custom.axum_routes')
    vim.cmd.cd(dir)
    vim.cmd.edit(file)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd('AxumRoutesFile')
  ]], { dir, file, line })
  return file
end

-- Picker rows once it has any, the selected one marked by a leading `>`.
local function rows()
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
    return vim.tbl_map(function(r) return (r:gsub('%s+$', '')) end, out or {})
  ]])
end

-- A utoipa path alone has no router prefix, so `…` stands in for it.
T['the file picker lists its endpoints with handler, doc and place'] = function()
  file_picker(1)
  eq(rows(), {
    '> GET    …/api/v1/users -> list_users  Lists users.  routes.rs\\src',
    '  DELETE …/api/v1/users/{id} -> drop_user  One user.  routes.rs\\src',
  })
end

T['the file picker starts on the endpoint around the cursor'] = function()
  file_picker(13)
  eq(vim.tbl_map(function(r) return r:sub(1, 1) end, rows()), { ' ', '>' })
end

T['the file picker previews the live buffer'] = function()
  local file = file_picker(1)
  rows()
  eq(child.lua([[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.api.nvim_buf_get_name(b) == ... and w ~= vim.fn.win_getid(vim.fn.winnr('#')) then
        return vim.api.nvim_win_get_config(w).relative ~= ''
      end
    end
    return false
  ]], { file }), true)
end

T['picking an endpoint opens its handler and gives the scroll back'] = function()
  local before = child.o.mousescroll
  local file = file_picker(1)
  rows()
  local during = child.o.mousescroll
  child.cmd('stopinsert')
  child.type_keys('j', '<CR>')
  child.lua('vim.wait(100)')
  eq({ during, child.o.mousescroll, child.api.nvim_buf_get_name(0), child.api.nvim_win_get_cursor(0)[1] },
    { 'ver:3,hor:1', before, file, 13 })
end

return T
