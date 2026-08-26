-- Hover documentation for SQL, in .sql buffers and inside injected query strings
-- (sqlx::query! and friends). No language server offers this: postgres-language-server
-- hovers schema objects and only with a live connection, and nothing at all documents
-- the language itself. Two offline sources stand in - the project's own migrations
-- (custom/sql_migration_index) and a Postgres reference table (custom/sql_keywords).

local index = require('custom.sql_migration_index')
local keywords = require('custom.sql_keywords')

local M = {}

-- A long migration comment is a design note; past this it buries the signature.
local MAX_DOC_LINES = 20
local MAX_CHANGE_LINES = 6

-- Longest multi-word entry in the table (`IS NOT DISTINCT FROM`).
local MAX_PHRASE = 4

local OPERATORS = {}
for name, entry in pairs(keywords) do
  if entry.kind == 'operator' then OPERATORS[#OPERATORS + 1] = name end
end
-- Longest first, so `->>` is preferred over the `->` inside it.
table.sort(OPERATORS, function(a, b) return #a > #b end)

-- position --------------------------------------------------------------------

-- Whether `row`/`col` sits in SQL: the whole buffer in a .sql file, or an injected
-- region elsewhere. Injections are what already paint sqlx queries, so this reuses
-- the ranges treesitter has and needs no separate notion of where a query starts.
local function in_sql(bufnr, row, col)
  local ft = vim.bo[bufnr].filetype
  if ft == 'sql' or ft == 'mysql' or ft == 'plsql' then return true end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return false end
  local got, lang = pcall(function()
    -- Injected regions exist only where the tree has been parsed. Parse this row
    -- alone, not the buffer: the panel asks on every cursor move.
    parser:parse({ row, row + 1 })
    local tree = parser:language_for_range({ row, col, row, col })
    return tree and tree:lang()
  end)
  return got and lang == 'sql'
end

-- Lines of the injected SQL region holding the cursor. In a .sql buffer there is no
-- region, so a window around the cursor stands in for the statement.
local WINDOW = 40

local function region_lines(bufnr, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok and parser then
    local got, range = pcall(function()
      local lt = parser:language_for_range({ row, col, row, col })
      if not lt or lt:lang() ~= 'sql' then return nil end
      for _, tree in pairs(lt:trees()) do
        local srow, _, erow, _ = tree:root():range()
        if srow <= row and row <= erow then return { srow, erow } end
      end
    end)
    if got and range then
      return vim.api.nvim_buf_get_lines(bufnr, range[1], range[2] + 1, false)
    end
  end
  return vim.api.nvim_buf_get_lines(bufnr, math.max(0, row - WINDOW), row + WINDOW, false)
end

-- Words that follow a table name but cannot be an alias.
local NOT_ALIAS = {}
for _, w in ipairs({
  'ON', 'WHERE', 'SET', 'VALUES', 'USING', 'LEFT', 'RIGHT', 'INNER', 'FULL', 'CROSS',
  'JOIN', 'GROUP', 'ORDER', 'LIMIT', 'OFFSET', 'HAVING', 'UNION', 'RETURNING', 'SELECT',
  'LATERAL', 'WITH', 'FOR', 'AND', 'OR', 'INTO', 'FROM', 'DO', 'DEFAULT', 'EXCEPT',
  'INTERSECT', 'WINDOW', 'FETCH', 'ONLY', 'NATURAL', 'TABLESAMPLE',
}) do NOT_ALIAS[w] = true end

-- Keywords that introduce a table name.
local INTRODUCES = { FROM = true, JOIN = true, INTO = true, UPDATE = true }

-- Word tokens of a line as {text, from, to}, 1-based and inclusive.
local function tokens(line)
  local out = {}
  for from, text, to in line:gmatch('()([%a_][%w_]*)()') do
    out[#out + 1] = { text = text, from = from, to = to - 1 }
  end
  return out
end

-- Tables the surrounding query names, keyed by both the table name and any alias, so
-- `l.city` resolves in `FROM locations l`. Narrowing a column to this set is what makes
-- a bare `content_id` answerable at all - it exists in dozens of tables project-wide.
local function scope_tables(lines)
  local words = {}
  for _, line in ipairs(lines) do
    for word in line:gmatch('[%a_][%w_%.]*') do words[#words + 1] = word end
  end

  local map = {}
  for i, word in ipairs(words) do
    if INTRODUCES[word:upper()] then
      local name = words[i + 1]
      if name and not NOT_ALIAS[name:upper()] then
        map[name:lower()] = name
        local after = words[i + 2]
        if after and after:upper() == 'AS' then after = words[i + 3] end
        if after and not NOT_ALIAS[after:upper()] and not after:find('%.') then
          map[after:lower()] = name
        end
      end
    end
  end
  return map
end

-- Index of the token covering `col` (0-based), or nil when the cursor is on space.
local function token_at(toks, col)
  for i, t in ipairs(toks) do
    if col + 1 >= t.from and col + 1 <= t.to then return i end
  end
end

-- Longest keyword phrase covering the token at `i`. Tries longer spans first so
-- `ON CONFLICT` wins over `ON`, and prefers the span starting furthest left.
local function phrase_at(toks, i)
  for len = MAX_PHRASE, 1, -1 do
    for start = math.max(1, i - len + 1), i do
      local last = start + len - 1
      if last <= #toks then
        local parts = {}
        for k = start, last do parts[#parts + 1] = toks[k].text:upper() end
        local key = table.concat(parts, ' ')
        if keywords[key] then return key, keywords[key] end
      end
    end
  end
end

-- Operator under the cursor, longest match first.
local function operator_at(line, col)
  for _, op in ipairs(OPERATORS) do
    local from = 1
    while true do
      local a, b = line:find(op, from, true)
      if not a then break end
      if col + 1 >= a and col + 1 <= b then return op, keywords[op] end
      from = a + 1
    end
  end
end

-- `alias.column` when the cursor is on either half; returns qualifier, column.
local function qualified_at(line, toks, i)
  local tok = toks[i]
  local before = line:sub(1, tok.from - 1)
  if before:match('%.%s*$') and toks[i - 1] and toks[i - 1].to == tok.from - 2 then
    return toks[i - 1].text, tok.text
  end
  -- Cursor on the qualifier itself: the column is the token straight after the dot.
  if line:sub(tok.to + 1, tok.to + 1) == '.' and toks[i + 1] and toks[i + 1].from == tok.to + 2 then
    return tok.text, toks[i + 1].text
  end
end

-- rendering -------------------------------------------------------------------

local function code_block(text)
  return { '```sql', text, '```' }
end

-- Trim a comment block to `limit`, saying how much was left out rather than
-- ending mid-sentence with no sign that anything is missing.
local function clamp(lines, limit)
  if #lines <= limit then return vim.deepcopy(lines) end
  local out = vim.list_slice(lines, 1, limit)
  out[#out + 1] = ('... (%d more lines in the migration)'):format(#lines - limit)
  return out
end

local function append_doc(out, doc, limit)
  if not doc or #doc == 0 then return end
  if #out > 0 then out[#out + 1] = '' end
  vim.list_extend(out, clamp(doc, limit))
end

-- Split a parameter list on commas at depth 0, so `NUMERIC(10, 2)` stays one argument.
local function split_args(text)
  local out, depth, start = {}, 0, 1
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
    elseif c == ',' and depth == 0 then
      out[#out + 1] = vim.trim(text:sub(start, i - 1))
      start = i + 1
    end
  end
  out[#out + 1] = vim.trim(text:sub(start))
  return out
end

-- A signature wider than the float wraps mid-argument, which is unreadable; past that
-- width give each parameter its own line, the way the migration itself declares them.
local SIG_WIDTH = 72

local function signature_lines(name, args, returns)
  local tail = returns and (' RETURNS ' .. returns) or ''
  local inner = (args or '()'):match('^%((.*)%)$') or ''
  local flat = name .. '(' .. vim.trim((inner:gsub('%s+', ' '))) .. ')' .. tail
  if #flat <= SIG_WIDTH or vim.trim(inner) == '' then return { flat } end

  local lines = { name .. '(' }
  local params = split_args(inner)
  for n, param in ipairs(params) do
    lines[#lines + 1] = '  ' .. (param:gsub('%s+', ' ')) .. (n < #params and ',' or '')
  end
  lines[#lines + 1] = ')' .. tail
  return lines
end

local function render_migration(entry)
  local out = {}
  if entry.kind == 'function' then
    out[#out + 1] = '```sql'
    vim.list_extend(out, signature_lines(entry.name, entry.args, entry.returns))
    out[#out + 1] = '```'
  elseif entry.kind == 'type' then
    vim.list_extend(out, code_block(('CREATE TYPE %s %s'):format(entry.name, entry.def or '')))
  else
    out[#out + 1] = '```sql'
    out[#out + 1] = ('%s (%s)'):format(entry.name, entry.kind)
    for _, c in ipairs(entry.cols or {}) do
      out[#out + 1] = ('  %-24s %s'):format(c.name, c.type or '')
    end
    out[#out + 1] = '```'
  end

  append_doc(out, entry.doc, MAX_DOC_LINES)
  if entry.change then
    out[#out + 1] = ''
    out[#out + 1] = ('**Last change** - %s:'):format(entry.change_file or '?')
    vim.list_extend(out, clamp(entry.change, MAX_CHANGE_LINES))
  end
  out[#out + 1] = ''
  out[#out + 1] = ('`%s:%d`'):format(entry.file, entry.lnum)
  return out
end

local function render_keyword(name, entry)
  local out = code_block(entry.sig or name)
  out[#out + 1] = ''
  out[#out + 1] = entry.doc
  out[#out + 1] = ''
  out[#out + 1] = ('_Postgres %s_'):format(entry.kind)
  return out
end

local function render_column(col, table_entry)
  local out = code_block(('%s.%s  %s'):format(table_entry.name, col.name, col.type or ''))
  if col.doc then
    out[#out + 1] = ''
    out[#out + 1] = col.doc
  end
  if col.decl and col.decl ~= col.type then
    out[#out + 1] = ''
    out[#out + 1] = ('Declared `%s`'):format(col.decl)
  end
  out[#out + 1] = ''
  out[#out + 1] = ('`%s:%d`'):format(table_entry.file, table_entry.lnum)
  return out
end

-- lookup ----------------------------------------------------------------------

-- A column name alone is the noisiest thing to resolve (`id`, `name` are everywhere),
-- so it answers only when few enough tables share it to still be informative.
local MAX_AMBIGUOUS = 3

local function render_hits(name, hits)
  if #hits == 0 then return nil end
  if #hits == 1 then return render_column(hits[1].col, hits[1].table) end

  local out = { ('`%s` is a column of %d tables:'):format(name, #hits), '' }
  for _, hit in ipairs(hits) do
    out[#out + 1] = ('- `%s.%s` %s'):format(hit.table.name, hit.col.name, hit.col.type or '')
  end
  return out
end

-- Columns named `name` among the tables this query mentions.
local function scoped_column(bufnr, name, scope)
  local hits, seen = {}, {}
  for _, table_name in pairs(scope) do
    local key = table_name:lower()
    if not seen[key] then
      seen[key] = true
      local col, entry = index.lookup_column(bufnr, table_name, name)
      if col then hits[#hits + 1] = { col = col, table = entry } end
    end
  end
  table.sort(hits, function(a, b) return a.table.name < b.table.name end)
  return render_hits(name, hits)
end

local function unqualified_column(bufnr, name)
  local hits = index.columns_named(bufnr, name)
  if not hits or #hits == 0 or #hits > MAX_AMBIGUOUS then return nil end
  return render_hits(name, hits)
end

-- Documentation for the cursor position in `win`, or nil when it is not on SQL or
-- nothing is known about the word. Synchronous: both sources are in-memory tables.
function M.lines(win)
  local bufnr = vim.api.nvim_win_get_buf(win)
  local pos = vim.api.nvim_win_get_cursor(win)
  local row, col = pos[1] - 1, pos[2]
  if not in_sql(bufnr, row, col) then return nil end

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line or line == '' then return nil end

  local toks = tokens(line)
  local i = token_at(toks, col)
  if not i then
    local op, entry = operator_at(line, col)
    return op and render_keyword(op, entry) or nil
  end
  local word = toks[i].text

  -- Scanning the region is the one non-trivial cost here, so only column lookups pay it.
  local scope
  local function in_scope()
    scope = scope or scope_tables(region_lines(bufnr, row, col))
    return scope
  end

  -- 1. `table.column` is the most specific signal available, so it goes first.
  local qualifier, column = qualified_at(line, toks, i)
  if qualifier and column then
    local name = in_scope()[qualifier:lower()] or qualifier
    local col_entry, table_entry = index.lookup_column(bufnr, name, column)
    if col_entry then return render_column(col_entry, table_entry) end
  end

  -- 2. The project's own functions, tables and types.
  local entry = index.lookup(bufnr, word)
  if entry then return render_migration(entry) end

  -- 3. Postgres itself, as a phrase where one fits (`ON CONFLICT`, `FOR EACH ROW`).
  local key, kw = phrase_at(toks, i)
  if kw then return render_keyword(key, kw) end

  -- 4. An operator the cursor happens to sit inside.
  local op, op_entry = operator_at(line, col)
  if op_entry then return render_keyword(op, op_entry) end

  -- 5. A bare column, resolved against the tables this query names.
  local scoped = scoped_column(bufnr, word, in_scope())
  if scoped then return scoped end

  -- 6. Failing that, project-wide - but only while few enough tables share the name.
  return unqualified_column(bufnr, word)
end

return M
