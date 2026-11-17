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

-- Captures at the first `needle` in `lines`, as `lang:capture`.
local function captures(lines, needle)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  child.cmd('noautocmd setlocal filetype=rust')
  return child.lua([[
    local needle = ...
    for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local col = line:find(needle, 1, true)
      if col then
        -- Captures come from the highlighter, as on screen.
        vim.treesitter.start(0, 'rust')
        vim.treesitter.get_parser(0):parse(true)
        local out = {}
        for _, c in ipairs(vim.treesitter.get_captures_at_pos(0, row - 1, col - 1)) do
          out[#out + 1] = c.lang .. ':' .. c.capture
        end
        return out
      end
    end
    error('needle not found: ' .. needle)
  ]], { needle })
end

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
    { 'tagged binding',       { '// language=sql', 'let q = "SELECT id \\', '    FROM users";' }, 'FROM' },
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
