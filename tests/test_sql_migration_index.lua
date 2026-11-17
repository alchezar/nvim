-- sql_migration_index: the project's own SQL objects, as a query file in the
-- project sees them after every migration has been replayed.
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function() child.restart({ '-u', 'tests/minimal_init.lua' }) end,
    post_once = child.stop,
  },
})

-- Throwaway sqlx-style project rooted by Cargo.lock, `files` in migrations/.
local function make_project(files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. '/migrations', 'p')
  vim.fn.writefile({}, root .. '/Cargo.lock')
  for name, lines in pairs(files) do
    vim.fn.writefile(lines, root .. '/migrations/' .. name)
  end
  return root
end

-- Columns of `users` as `name TYPE`, seen from a query file in the project.
local function users_columns(root)
  child.cmd('edit ' .. vim.fn.fnameescape(root .. '/query.sql'))
  return child.lua([[
    local users = require('custom.sql_migration_index').lookup(0, 'users')
    assert(users, 'table users is not in the index')
    return vim.tbl_map(function(c) return c.name .. ' ' .. c.type end, users.cols)
  ]])
end

local CREATE_USERS = {
  'CREATE TABLE users (',
  '  id BIGINT PRIMARY KEY,',
  '  email TEXT NOT NULL',
  ');',
}

T['ALTER TABLE users'] = new_set({
  parametrize = {
    -- Constraint and default changes leave the column as it was.
    { 'ALTER COLUMN email DROP NOT NULL',              { 'id BIGINT', 'email TEXT' } },
    { 'ALTER COLUMN email SET NOT NULL',               { 'id BIGINT', 'email TEXT' } },
    { 'ALTER COLUMN email DROP DEFAULT',               { 'id BIGINT', 'email TEXT' } },
    { "ALTER COLUMN email SET DEFAULT 'none'",         { 'id BIGINT', 'email TEXT' } },
    -- Both spellings of a retype.
    { 'ALTER COLUMN email TYPE VARCHAR(320)',          { 'id BIGINT', 'email VARCHAR(320)' } },
    { 'ALTER COLUMN email SET DATA TYPE VARCHAR(320)', { 'id BIGINT', 'email VARCHAR(320)' } },
    -- The actions that do change the list; the COLUMN keyword is optional.
    { 'DROP COLUMN email',                             { 'id BIGINT' } },
    { 'DROP email',                                    { 'id BIGINT' } },
    { 'RENAME COLUMN email TO mail',                   { 'id BIGINT', 'mail TEXT' } },
    { 'ADD COLUMN age INT',                            { 'id BIGINT', 'email TEXT', 'age INT' } },
    { 'ADD CONSTRAINT users_email_key UNIQUE (email)', { 'id BIGINT', 'email TEXT' } },
    { 'ADD COLUMN age INT, DROP COLUMN email',         { 'id BIGINT', 'age INT' } },
  },
})

-- Before ff810bc, ALTER COLUMN ... DROP NOT NULL/DEFAULT dropped the column.
T['ALTER TABLE users']['replays onto the columns'] = function(action, want)
  local root = make_project({
    ['0001_init.sql'] = CREATE_USERS,
    ['0002_alter.sql'] = { 'ALTER TABLE users ' .. action .. ';' },
  })
  eq(users_columns(root), want)
end

-- Write `tree` (path -> lines) under a fresh dir and return it.
local function make_tree(tree)
  local root = vim.fn.tempname()
  for path, lines in pairs(tree) do
    vim.fn.mkdir(vim.fs.dirname(root .. '/' .. path), 'p')
    vim.fn.writefile(lines, root .. '/' .. path)
  end
  return root
end

-- Kind and doc of `name` from a query file at `query` under `root`, or false.
local function lookup(root, query, name)
  child.cmd('edit ' .. vim.fn.fnameescape(root .. '/' .. query))
  return child.lua([[
    local e = require('custom.sql_migration_index').lookup(0, ...)
    return e and { e.kind, table.concat(e.doc, ' ') } or false
  ]], { name })
end

-- Before 099dd7e, only the repo root was searched, so a nested service with its
-- own migrations next to its Cargo.toml had no index.
T['nested service uses its own migrations'] = function()
  local root = make_tree({
    ['.git/HEAD'] = {},
    ['services/api/Cargo.toml'] = {},
    ['services/api/migrations/0001.sql'] = { 'CREATE TABLE orders (id INT);' },
  })
  eq(lookup(root, 'services/api/src/q.sql', 'orders'), { 'table', '' })
end

T['sql dir outside a package is not migrations'] = function()
  local root = make_tree({
    ['.git/HEAD'] = {},
    ['migrations/0001.sql'] = { 'CREATE TABLE users (id INT);' },
    ['docs/sql/notes.sql'] = { 'CREATE TABLE notes (id INT);' },
  })
  eq(lookup(root, 'docs/q.sql', 'users'), { 'table', '' })
  eq(lookup(root, 'docs/q.sql', 'notes'), false)
end

T['docs come from COMMENT ON, else the comment above'] = function()
  local root = make_tree({
    ['Cargo.lock'] = {},
    ['migrations/0001.sql'] = {
      '-- People who can sign in.',
      'CREATE TABLE users (id INT);',
      '-- Shipping orders.',
      'CREATE TABLE orders (id INT);',
      "COMMENT ON TABLE orders IS 'Orders placed by users.';",
    },
  })
  eq(lookup(root, 'q.sql', 'users'), { 'table', 'People who can sign in.' })
  eq(lookup(root, 'q.sql', 'orders'), { 'table', 'Orders placed by users.' })
end

T['a later CREATE OR REPLACE keeps the first doc, DROP removes'] = function()
  local root = make_tree({
    ['Cargo.lock'] = {},
    ['migrations/0001.sql'] = {
      '-- Total of an order.',
      'CREATE FUNCTION order_total(id INT) RETURNS INT AS $$ SELECT 1 $$ LANGUAGE sql;',
      'CREATE TABLE tmp (id INT);',
    },
    ['migrations/0002.sql'] = {
      '-- Fix rounding.',
      'CREATE OR REPLACE FUNCTION order_total(id INT) RETURNS INT AS $$ SELECT 2 $$ LANGUAGE sql;',
      'DROP TABLE tmp;',
    },
  })
  eq(lookup(root, 'q.sql', 'order_total'), { 'function', 'Total of an order.' })
  eq(lookup(root, 'q.sql', 'tmp'), false)
end

return T
