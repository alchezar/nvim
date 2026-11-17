-- <leader>sl (utils.search_rust_idioms) searches Rust lines worth a second
-- look. Checked by which buffer lines the resulting search pattern hits.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

-- Whether the search the mapping starts hits `line`.
local function hits(line)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  return child.lua([[
    require('config.utils').search_rust_idioms()
    vim.api.nvim_feedkeys('', 'x', false)
    return #vim.fn.matchbufline(vim.api.nvim_get_current_buf(), vim.fn.getreg('/'), 1, '$') > 0
  ]])
end

T['hit'] = new_set({
  parametrize = {
    { 'let x: u32 = 1;' },
    { 'let mut v: Vec<u8> = vec![];' },
    { 'fn connect(pool: sqlx::PgPool) {}' },
    { 'query.execute(&mut *tx).await?;' },
    { 'use std::{fmt, io};' },
    -- Before d1698f5, a qualified variant looked like an import line and was
    -- skipped.
    { '        sqlx::Error::RowNotFound,' },
  },
})
T['hit']['is found'] = function(line) eq(hits(line), true) end

T['miss'] = new_set({
  parametrize = {
    { 'let x = 1;' },
    -- Before 7fed973, `let Enum::` read as a `let x:` annotation.
    { 'let Shape::Circle(r) = shape;' },
    -- Before cc2a8bc, a line inside a multi-line `use` block.
    { '    postgres::PgPool,' },
    -- Before 23fdf0a, any `&mut *x` reborrow counted, not only transactions.
    { 'read(&mut *conn).await?;' },
    -- Before f95c618, a type path quoted in a doc comment.
    { '/// Takes a `sqlx::PgPool` from the state.' },
  },
})
T['miss']['is skipped'] = function(line) eq(hits(line), false) end

return T
