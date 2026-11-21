-- SQL hover docs from custom/sql_hover.lua, in .sql files and in sqlx queries
-- injected into Rust. The project's migrations answer for its own objects, a
-- Postgres reference for the language itself.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true })
      -- An sqlx project with one migration.
      root = vim.fn.tempname()
      vim.fn.mkdir(root .. '/migrations', 'p')
      vim.fn.writefile({}, root .. '/Cargo.lock')
      vim.fn.writefile({
        '-- People who can sign in.',
        'CREATE TABLE users (id BIGINT PRIMARY KEY, email TEXT NOT NULL, city_id BIGINT);',
        'CREATE TABLE cities (id BIGINT PRIMARY KEY, name TEXT, city_id BIGINT);',
        'CREATE TABLE towns (id BIGINT, name TEXT);',
        'CREATE TABLE villages (id BIGINT, name TEXT);',
        'CREATE TABLE farms (id BIGINT, name TEXT);',
        '-- Adds two numbers.',
        'CREATE FUNCTION add_two(a INT, b INT) RETURNS INT AS $$ SELECT a + b $$ LANGUAGE sql;',
      }, root .. '/migrations/0001_init.sql')
      child.lua('vim.cmd.cd(...)', { root })
    end,
    post_once = child.stop,
  },
})

-- Hover lines with the cursor `off` bytes into the first `needle` of `lines`,
-- written to `name` in the project; false when there is nothing to show.
local function hover(name, lines, needle, off)
  vim.fn.writefile(lines, root .. '/' .. name)
  return child.lua([[
    local file, needle, off = ...
    vim.cmd.edit(file)
    for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local col = line:find(needle, 1, true)
      if col then
        vim.api.nvim_win_set_cursor(0, { row, col - 1 + (off or 0) })
        return require('custom.sql_hover').lines(0) or false
      end
    end
    error('needle not found: ' .. needle)
  ]], { root .. '/' .. name, needle, off })
end

-- The code line a hover opens with, after its ```sql fence.
local function head(name, lines, needle, off)
  local got = hover(name, lines, needle, off)
  return got and got[2]
end

T['a postgres built-in is documented with its kind'] = function()
  local got = hover('q.sql', { 'SELECT coalesce(a, b) FROM t' }, 'coalesce')
  eq({ got[2]:match('^coalesce%('), got[#got] }, { 'coalesce(', '_Postgres function_' })
end

T['the longest phrase under the cursor wins'] = function()
  local q = { 'SELECT 1 WHERE a IS NOT DISTINCT FROM b', 'ON CONFLICT (id) DO NOTHING' }
  eq({ head('q.sql', q, 'NOT'), head('q.sql', q, 'ON CONFLICT') }, {
    'a IS NOT DISTINCT FROM b',
    'ON CONFLICT [(cols) | ON CONSTRAINT name] DO { NOTHING | UPDATE SET ... }',
  })
end

T['an operator is documented from inside it, longest first'] = function()
  eq(head('q.sql', { "SELECT data->>'k' FROM t" }, '->>', 1), "json ->> 'key'")
end

T['a cast type names the rust type sqlx decodes it into'] = function()
  local got = hover('q.sql', { 'SELECT $1::uuid' }, 'uuid')
  eq(vim.tbl_contains(got or {}, 'sqlx decodes this as `uuid::Uuid`'), true)
end

T['a table from the migrations shows its columns, doc and place'] = function()
  eq(hover('q.sql', { 'SELECT * FROM users' }, 'users'), {
    '```sql',
    'users (table)',
    '  id                       BIGINT',
    '  email                    TEXT',
    '  city_id                  BIGINT',
    '```',
    '',
    'People who can sign in.',
    '',
    '`migrations/0001_init.sql:2`',
  })
end

T['a function from the migrations shows its signature and doc'] = function()
  local got = hover('q.sql', { 'SELECT add_two(1, 2)' }, 'add_two')
  eq({ got[2], got[5] }, { 'add_two(a INT, b INT) RETURNS INT', 'Adds two numbers.' })
end

T['a column resolves through the alias of its table'] = function()
  local q = { 'SELECT u.email, c.name FROM users u', 'JOIN cities AS c ON c.id = u.city_id' }
  eq({ head('q.sql', q, 'email'), head('q.sql', q, 'u.email'), head('q.sql', q, 'name') },
    { 'users.email  TEXT', 'users.email  TEXT', 'cities.name  TEXT' })
end

T['a bare column resolves against the tables its query names'] = function()
  eq(head('q.sql', { 'SELECT city_id FROM users' }, 'city_id'), 'users.city_id  BIGINT')
end

T['an unscoped column lists a few tables, but not many'] = function()
  eq({ hover('q.sql', { 'SELECT city_id' }, 'city_id'), hover('q.sql', { 'SELECT name' }, 'name') }, {
    { '`city_id` is a column of 2 tables:', '', '- `cities.city_id` BIGINT', '- `users.city_id` BIGINT' },
    false,
  })
end

T['an sqlx query in rust gets the docs, the rust around it none'] = function()
  local rs = { 'fn f() {', '    let r = sqlx::query!("SELECT id FROM users WHERE id = $1", id);', '}' }
  eq({ head('a.rs', rs, 'users'), head('a.rs', rs, 'id ='), hover('a.rs', rs, 'let') },
    { 'users (table)', 'users.id  BIGINT', false })
end

return T
