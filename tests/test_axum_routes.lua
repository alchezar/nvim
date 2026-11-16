-- axum_routes.collect: which `METHOD /path` endpoints a Rust file yields,
-- from utoipa attrs and the route comments over handlers.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function() child.setup({ plugins = { 'plenary.nvim', 'telescope.nvim' } }) end,
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

-- 7d08bd1: any comment naming a route counted, even over a type.
T['route comment over a type is ignored'] = function()
  eq(endpoints({ '// GET /api/users', 'pub struct UsersPage {}' }), {})
end

-- 5dc131e: prose naming another endpoint became a ghost entry.
T['route mentioned in prose is ignored'] = function()
  local lines = with({ '/// Same data as GET /api/legacy, newer shape.' },
    utoipa('get', '/users', 'list_users'))
  eq(endpoints(lines), { 'GET /users list_users' })
end

-- f3d565e: a documented query string broke the match with utoipa's path.
T['query string in the comment still matches'] = function()
  eq(endpoints(with({ '// GET /api/users?page=1' }, utoipa('get', '/users', 'list_users'))),
    { 'GET /api/users?page=1 list_users' })
end

T['bare handler needs a banner that is only the route'] = function()
  eq(endpoints({ '// POST /api/login', 'pub async fn login() {}' }), { 'POST /api/login login' })
  eq(endpoints({ '// see POST /api/login for details', 'fn helper() {}' }), {})
end

return T
