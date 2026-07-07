-- Lexical fallback highlight for PL/pgSQL bodies ($$ ... $$).
-- The sql grammar can't parse plpgsql, so the sql-injection (after/queries/sql) leaves
-- procedural tokens (FOREACH/LOOP, calls in `x := f(...)`, strings, variables) uncaptured.
-- This paints them via buffer-local extmarks at a priority BELOW treesitter (100), so real
-- captures always win (valid SQL untouched) and nothing leaks to other buffers.

local theme = require('config.theme_colors')

local ns = vim.api.nvim_create_namespace('plpgsql_lexical')
local PRIO = (vim.hl and vim.hl.priorities.treesitter or 100) - 10

-- Custom groups: grey variables (built-in @variable is near-white), cyan types (match
-- @type.builtin.sql), orange parameters, emerald $$ delimiters.
local function set_hl()
  vim.api.nvim_set_hl(0, 'PlpgsqlVariable', { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'PlpgsqlType', { fg = theme.cyan })
  vim.api.nvim_set_hl(0, 'PlpgsqlParam', { fg = theme.orange })
  vim.api.nvim_set_hl(0, 'PlpgsqlDelim', { fg = theme.emerald })
end
set_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_hl })

-- Control/operator keywords the sql grammar routinely drops into ERROR (stay bare).
local KEYWORDS = {}
for _, k in ipairs({
  'IF', 'THEN', 'ELSE', 'ELSIF', 'ELSEIF', 'END', 'BEGIN', 'DECLARE', 'RETURN', 'RETURNS',
  'LOOP', 'FOREACH', 'CONTINUE', 'EXIT', 'WHILE', 'FOR', 'RAISE', 'EXECUTE', 'PERFORM',
  'NOTICE', 'EXCEPTION', 'CASE', 'WHEN', 'AND', 'OR', 'NOT', 'IS', 'NULL', 'IN', 'LIKE',
  'ILIKE', 'ESCAPE', 'ARRAY', 'BETWEEN',
}) do KEYWORDS[k] = true end

-- Types get their own color so they never fall back to the grey variable group.
local TYPES = {}
for _, t in ipairs({
  'TEXT', 'INTEGER', 'INT', 'BIGINT', 'SMALLINT', 'BOOLEAN', 'BOOL', 'NUMERIC', 'DECIMAL',
  'REAL', 'VARCHAR', 'CHAR', 'CHARACTER', 'DATE', 'TIMESTAMP', 'TIMESTAMPTZ', 'TIME',
  'UUID', 'JSONB', 'JSON', 'BYTEA', 'FLOAT', 'DOUBLE', 'SERIAL', 'BIGSERIAL', 'INTERVAL',
}) do TYPES[t] = true end

local function mark(buf, row, col, col_end, group)
  vim.api.nvim_buf_set_extmark(buf, ns, row, col, { end_col = col_end, hl_group = group, priority = PRIO })
end

local function scan_line(buf, row, line, params)
  -- 1) string literals -> @string; mask them so their contents aren't rescanned below.
  local masked = line
  for _, q in ipairs({ "'", '"' }) do
    local pat = q .. '[^' .. q .. ']*' .. q
    for s, lit in line:gmatch('()(' .. pat .. ')') do
      mark(buf, row, s - 1, s - 1 + #lit, '@string')
    end
    masked = masked:gsub(pat, function(m) return (' '):rep(#m) end)
  end
  -- 2) identifiers: parameter / keyword / type / call / everything else is a variable.
  for s, word, nxt in masked:gmatch('()([%a_][%w_]*)()') do
    local col, group = s - 1, 'PlpgsqlVariable'
    if params[word] then
      group = 'PlpgsqlParam'
    elseif KEYWORDS[word:upper()] then
      group = '@keyword'
    elseif TYPES[word:upper()] then
      group = 'PlpgsqlType'
    elseif masked:sub(nxt):match('^%s*%(') then
      group = '@function.call'
    end
    mark(buf, row, col, col + #word, group)
  end
  -- 3) whole-word numbers (skip digits inside identifiers like i32) and procedural operators.
  for s, num in masked:gmatch('()(%d+)') do
    if not masked:sub(s - 1, s - 1):match('[%w_]') then mark(buf, row, s - 1, s - 1 + #num, '@number') end
  end
  for s in masked:gmatch('():=') do mark(buf, row, s - 1, s + 1, '@operator') end
  for s in masked:gmatch('()||') do mark(buf, row, s - 1, s + 1, '@operator') end
end

-- Harvest parameter names from CREATE FUNCTION signatures and paint each occurrence.
local function collect_params(buf)
  local params = {}
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'sql')
  if not ok then return params end
  local function walk(n)
    if n:type() == 'function_argument' then
      local a, b, c, d = n:range()
      if a == c then
        local text = vim.api.nvim_buf_get_text(buf, a, b, c, d, {})[1] or ''
        local lead, name = text:match('^(%s*)([%a_][%w_]*)')
        if name and not TYPES[name:upper()] then
          params[name] = true
          mark(buf, a, b + #lead, b + #lead + #name, 'PlpgsqlParam') -- signature occurrence
        end
      end
    end
    for ch in n:iter_children() do walk(ch) end
  end
  walk(parser:parse()[1]:root())
  return params
end

local function refresh(buf)
  if vim.bo[buf].filetype ~= 'sql' then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local params = collect_params(buf)
  local in_body = false
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find('%$%$') then
      in_body = not in_body -- delimiter line: toggle body state, but do color the $$
      for s in line:gmatch('()%$%$') do mark(buf, i - 1, s - 1, s + 1, 'PlpgsqlDelim') end
    elseif in_body then
      scan_line(buf, i - 1, line, params)
    end
  end
end

local group = vim.api.nvim_create_augroup('plpgsql_lexical', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'sql',
  callback = function(a) refresh(a.buf) end,
})
vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
  group = group,
  callback = function(a) refresh(a.buf) end,
})
