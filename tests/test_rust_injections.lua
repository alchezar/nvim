-- SQL (and redis Lua) injected into Rust strings by queries/rust,
-- checked by the captures that actually paint the first keyword.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function() child.setup({ treesitter = true }) end,
    post_once = child.stop,
  },
})

local function captures(lines, needle) return H.captures(child, 'rust', lines, needle) end

local function has(caps, prefix)
  for _, c in ipairs(caps) do
    if c:sub(1, #prefix) == prefix then return true end
  end
  return false
end

T['SQL keyword'] = new_set({
  parametrize = {
    { 'sqlx macro',           { 'let r = sqlx::query!("SELECT id FROM users");' } },
    -- Before ca41487, a multi-line plain string got no SQL region at all.
    { 'multi-line string',    { 'let r = sqlx::query!("', '    SELECT id FROM users', '");' } },
    { 'raw string',           { 'let r = sqlx::query!(r#"SELECT id FROM users"#);' } },
    { 'bare macro',           { 'let r = query_as!(User, "SELECT id FROM users");' } },
    { 'function form',        { 'let n = sqlx::query_scalar::<_, i64>("SELECT count(*) FROM users");' } },
    { 'QueryBuilder',         { 'let mut qb = QueryBuilder::new("SELECT id FROM users");' } },
    { 'tagged format!',       { 'let q = format!(/* language=sql */ "SELECT id FROM {t}");' } },
    -- 3a67ee0. A `\` continuation split the string, losing words.
    { 'tagged binding',       { '// language=sql', 'let q = "SELECT id \\', '    FROM users";' },       'FROM' },
    { 'tagged call argument', { 'qb.push(/* language=sql */ "SELECT id FROM users");' } },
  },
})

T['SQL keyword']['is highlighted as SQL'] = function(_, lines, needle)
  local caps = captures(lines, needle or 'SELECT')
  eq({ sql = has(caps, 'sql:keyword'), caps = caps }, { sql = true, caps = caps })
end

T['plain Rust string stays Rust'] = new_set({
  parametrize = {
    { 'untagged binding', { 'let q = "SELECT id FROM users";' } },
    { 'other macro',      { 'println!("SELECT {}", id);' } },
  },
})

T['plain Rust string stays Rust']['has no SQL'] = function(_, lines)
  eq(has(captures(lines, 'SELECT'), 'sql:'), false)
end

T['redis Script body is Lua'] = function()
  local caps = captures({ [[let s = redis::Script::new(r"return redis.call('GET', KEYS[1])");]] }, 'return')
  eq({ lua = has(caps, 'lua:keyword'), caps = caps }, { lua = true, caps = caps })
end

return T
