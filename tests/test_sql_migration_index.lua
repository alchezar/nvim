-- ALTER TABLE replayed on top of CREATE TABLE in sql_migration_index. Guards
-- ff810bc, where ALTER COLUMN ... DROP NOT NULL/DEFAULT dropped the column.
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

T['ALTER TABLE users']['replays onto the columns'] = function(action, want)
  local root = make_project({
    ['0001_init.sql'] = CREATE_USERS,
    ['0002_alter.sql'] = { 'ALTER TABLE users ' .. action .. ';' },
  })
  eq(users_columns(root), want)
end

return T
