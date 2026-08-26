-- Index of the project's own SQL objects, parsed out of its migrations directory.
-- Postgres keeps no doc-comment in code, so a description comes from `COMMENT ON`
-- first, else from the comment block glued directly above the statement.
-- Files are read in name order and later ones overwrite earlier: CREATE OR REPLACE
-- is how a function evolves, so only the last definition describes the live one.

local utils = require('config.utils')

local M = {}

-- Checked in order, relative to the project root. Rollback dirs (`migrations_down`)
-- are deliberately absent - an older definition there would shadow the live one.
local DIRS = { 'migrations', 'db/migrations', 'supabase/migrations', 'migration', 'sql' }

local MAX_FILES = 500
local MAX_LINES = 5000

-- Trail the return type of a function; the type itself ends at the first of these.
local MODIFIERS = {
  'LANGUAGE', 'IMMUTABLE', 'STABLE', 'VOLATILE', 'SECURITY', 'STRICT',
  'PARALLEL', 'COST', 'ROWS', 'WINDOW', 'CALLED', 'LEAKPROOF', 'SET', 'TRANSFORM',
}

-- Type names that are more than one word, longest first so the prefix test is greedy.
local MULTIWORD_TYPES = {
  'TIMESTAMP WITHOUT TIME ZONE', 'TIMESTAMP WITH TIME ZONE',
  'TIME WITHOUT TIME ZONE', 'TIME WITH TIME ZONE',
  'CHARACTER VARYING', 'DOUBLE PRECISION', 'BIT VARYING',
}

-- Table body entries that constrain rather than declare a column.
local CONSTRAINTS = {
  PRIMARY = true, FOREIGN = true, UNIQUE = true, CHECK = true, CONSTRAINT = true,
  EXCLUDE = true, LIKE = true, DEFERRABLE = true,
}

-- text helpers ----------------------------------------------------------------

-- Comment block above `lnum`; code, or a second blank line, ends it. One blank line
-- between the block and its statement is a common layout, so it does not detach them -
-- but stopping at the next blank keeps a migration's preamble out of a later statement.
local function comment_above(lines, lnum)
  local out = {}
  local i = lnum - 1
  if lines[i] and vim.trim(lines[i]) == '' then i = i - 1 end
  while i >= 1 do
    local body = lines[i]:match('^%s*%-%-%s?(.*)$')
    if not body then break end
    table.insert(out, 1, body)
    i = i - 1
  end
  -- A rule of repeated punctuation ruling off a section is decoration, not the doc.
  local function is_rule(line) return vim.trim(line):match('^[%-=*_~#]*$') ~= nil end
  while out[1] and is_rule(out[1]) do table.remove(out, 1) end
  while out[#out] and is_rule(out[#out]) do table.remove(out) end
  return out
end

-- Statement starting at `lnum` as one line: comments stripped, whitespace collapsed.
local function statement(lines, lnum, limit)
  local parts = {}
  for i = lnum, math.min(lnum + limit, #lines) do
    local line = lines[i]:gsub('%-%-.*$', '')
    parts[#parts + 1] = vim.trim(line)
    if line:find(';', 1, true) then break end
  end
  return (table.concat(parts, ' '):gsub('%s+', ' '))
end

-- Index of the `)` closing the `(` at `open`; quoted text is skipped.
local function close_paren(text, open)
  local depth, quoted = 0, false
  for i = open, #text do
    local c = text:sub(i, i)
    if c == "'" then
      quoted = not quoted
    elseif not quoted then
      if c == '(' then
        depth = depth + 1
      elseif c == ')' then
        depth = depth - 1
        if depth == 0 then return i end
      end
    end
  end
end

-- Split on commas at nesting depth 0, so `NUMERIC(12, 2)` stays one entry.
local function split_commas(text)
  local out, depth, quoted, start = {}, 0, false, 1
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "'" then
      quoted = not quoted
    elseif not quoted then
      if c == '(' then
        depth = depth + 1
      elseif c == ')' then
        depth = depth - 1
      elseif c == ',' and depth == 0 then
        out[#out + 1] = vim.trim(text:sub(start, i - 1))
        start = i + 1
      end
    end
  end
  out[#out + 1] = vim.trim(text:sub(start))
  return out
end

-- Cut a return type at the first trailing modifier keyword.
local function cut_modifiers(text)
  local upper, cut = text:upper(), #text + 1
  for _, kw in ipairs(MODIFIERS) do
    local at = upper:find('%f[%w]' .. kw .. '%f[%W]')
    if at and at < cut then cut = at end
  end
  return vim.trim(text:sub(1, cut - 1))
end

-- The type at the head of a column declaration, without the constraints trailing it:
-- a table listing wants `VARCHAR(255)`, not the whole `... NOT NULL REFERENCES ...`.
local function base_type(decl)
  local upper = decl:upper()
  for _, name in ipairs(MULTIWORD_TYPES) do
    if upper:find('^' .. name:gsub(' ', '%%s+')) then return name end
  end
  local head = decl:match('^([%a_][%w_]*%s*%b())') or decl:match('^([%a_][%w_]*)')
  if not head then return decl end
  -- An array suffix belongs to the type, and repeats for higher dimensions.
  local rest, suffix = decl:sub(#head + 1), ''
  while true do
    local dim = rest:match('^%s*%[%s*%]')
    if not dim then break end
    suffix, rest = suffix .. '[]', rest:sub(#dim + 1)
  end
  return (head:gsub('%s+', '')) .. suffix
end

-- `IF NOT EXISTS` / `IF EXISTS` sit between the keyword and the name; drop them.
local function strip_if_exists(text)
  local s, e = text:upper():find('%f[%w]IF%s+NOT%s+EXISTS%f[%W]')
  if not s then s, e = text:upper():find('%f[%w]IF%s+EXISTS%f[%W]') end
  if not s then return text end
  return text:sub(1, s - 1) .. text:sub(e + 1)
end

-- Object name following the keyword ending at `pos`, plus the position after it.
local function name_after(text, pos)
  return text:match('^%s*"?([%w_%.]+)"?%s*()', pos)
end

-- statement parsers -----------------------------------------------------------

-- A later CREATE OR REPLACE is almost always a fix, and its comment says what the fix
-- was ("replace the dropped content_type column"), not what the object is for. Keep the
-- original description as the doc and file the newer comment separately as the change.
local function keep_doc(store, key, entry)
  local prev = store[key]
  if prev and #prev.doc > 0 then
    if #entry.doc > 0 then
      entry.change, entry.change_file = entry.doc, entry.file
    else
      -- Carry the last change that explained itself; a silent redefinition after it
      -- would otherwise erase the only note saying why the object was touched.
      entry.change, entry.change_file = prev.change, prev.change_file
    end
    entry.doc, entry.doc_file, entry.explicit = prev.doc, prev.doc_file, prev.explicit
  end
  store[key] = entry
end

-- CREATE [OR REPLACE] FUNCTION name(args) RETURNS type <modifiers> AS $$ body $$
local function parse_function(index, lines, i, file)
  local parts, header = {}, nil
  for j = i, math.min(i + 40, #lines) do
    parts[#parts + 1] = vim.trim((lines[j]:gsub('%-%-.*$', '')))
    local joined = (table.concat(parts, ' '):gsub('%s+', ' '))
    -- The body opens at the dollar quote (or a plain literal); the rest is signature.
    header = joined:match('^(.-)%s+[Aa][Ss]%s*%$') or joined:match("^(.-)%s+[Aa][Ss]%s*'")
    if header then break end
    if joined:find(';', 1, true) then
      header = joined:gsub(';.*$', '')
      break
    end
  end
  if not header then return end

  local at = header:upper():find('%f[%w]FUNCTION%f[%W]')
  if not at then return end
  local name, pos = name_after(header, at + #'FUNCTION')
  if not name then return end

  local args = '()'
  if header:sub(pos, pos) == '(' then
    local close = close_paren(header, pos)
    if not close then return end
    args = header:sub(pos, close)
    pos = close + 1
  end

  local tail = header:sub(pos)
  local returns
  local rat = tail:upper():find('%f[%w]RETURNS%f[%W]')
  if rat then returns = cut_modifiers(tail:sub(rat + #'RETURNS')) end

  local lang
  local lat = tail:upper():find('%f[%w]LANGUAGE%f[%W]')
  if lat then lang = tail:sub(lat + #'LANGUAGE'):match('^%s*([%w_]+)') end

  keep_doc(index.functions, name:lower(), {
    kind = 'function',
    name = name,
    args = args,
    returns = returns,
    lang = lang,
    doc = comment_above(lines, i),
    doc_file = file,
    file = file,
    lnum = i,
  })
end

-- COMMENT ON <kind> name IS 'text' - Postgres' own doc-comment, so it wins over
-- a comment block. The literal may span lines; '' is an escaped quote inside it.
local function parse_comment_on(index, lines, i, file)
  local parts = {}
  for j = i, math.min(i + 60, #lines) do
    parts[#parts + 1] = vim.trim(lines[j])
    local joined = table.concat(parts, '\n')
    local at = joined:upper():find('%f[%w]IS%f[%W]')
    if at then
      local rest = joined:sub(at + #'IS')
      local q = rest:find("'", 1, true)
      if q then
        local chars, k, body = {}, q + 1, nil
        while k <= #rest do
          local c = rest:sub(k, k)
          if c == "'" then
            if rest:sub(k + 1, k + 1) == "'" then
              chars[#chars + 1] = "'"
              k = k + 2
            else
              body = table.concat(chars)
              break
            end
          else
            chars[#chars + 1] = c
            k = k + 1
          end
        end
        -- No closing quote yet: the literal runs on, so pull in the next line.
        if body then
          local head = strip_if_exists(joined:sub(1, at - 1))
          local kind = head:upper():match('^%s*COMMENT%s+ON%s+(%a+)')
          if not kind then return end
          local kat = head:upper():find('%f[%w]' .. kind .. '%f[%W]')
          local name = name_after(head, kat + #kind)
          if not name then return end

          -- The literal is indented on continuation lines; reflow it into one paragraph.
          local doc = vim.split((body:gsub('%s*\n%s*', ' ')), '\n', { plain = true })
          local store = ({ FUNCTION = index.functions, PROCEDURE = index.functions,
            TABLE = index.tables, VIEW = index.tables, TYPE = index.types })[kind]
          if store then
            local entry = store[name:lower()]
            if entry then
              -- Written to be read, so it outranks any comment block, now or later.
              entry.doc, entry.doc_file, entry.explicit = doc, file, true
            end
          elseif kind == 'COLUMN' then
            local tbl, col = name:match('^(.+)%.([^%.]+)$')
            local entry = tbl and index.tables[tbl:lower()]
            if entry and entry.cols then
              for _, c in ipairs(entry.cols) do
                if c.name:lower() == col:lower() then c.doc = vim.trim((body:gsub('%s+', ' '))) end
              end
            end
          end
          return
        end
      end
    end
  end
end

-- CREATE TABLE name ( col type ..., CONSTRAINT ... );
local function parse_table(index, lines, i, file)
  local stmt = strip_if_exists(statement(lines, i, 300))
  local at = stmt:upper():find('%f[%w]TABLE%f[%W]')
  if not at then return end
  local name, pos = name_after(stmt, at + #'TABLE')
  if not name then return end

  local open = stmt:find('(', pos, true)
  local cols = {}
  if open then
    local close = close_paren(stmt, open)
    for _, entry in ipairs(split_commas(stmt:sub(open + 1, (close or #stmt + 1) - 1))) do
      local col, rest = entry:match('^"?([%w_]+)"?%s+(.*)$')
      if col and not CONSTRAINTS[col:upper()] then
        cols[#cols + 1] = { name = col, type = base_type(rest), decl = rest }
      end
    end
  end

  keep_doc(index.tables, name:lower(), {
    kind = 'table',
    name = name,
    cols = cols,
    doc = comment_above(lines, i),
    doc_file = file,
    file = file,
    lnum = i,
  })
end

-- ALTER TABLE name ADD/DROP/RENAME COLUMN ... - migrations grow a table this way,
-- so the column list is only right if these are replayed on top of CREATE TABLE.
local function parse_alter_table(index, lines, i, file)
  local stmt = strip_if_exists(statement(lines, i, 100))
  local at = stmt:upper():find('%f[%w]TABLE%f[%W]')
  if not at then return end
  local name, pos = name_after(stmt, at + #'TABLE')
  local entry = name and index.tables[name:lower()]
  if not entry then return end
  entry.file, entry.lnum = file, i -- the newest migration that touched it

  -- A renamed table keeps its whole history under the new name; leaving the old key
  -- behind would answer for a name the schema no longer has.
  local renamed = stmt:sub(pos):match('^%s*[Rr][Ee][Nn][Aa][Mm][Ee]%s+[Tt][Oo]%s+"?([%w_]+)"?')
  if renamed then
    index.tables[name:lower()] = nil
    entry.name, entry.file, entry.lnum = renamed, file, i
    index.tables[renamed:lower()] = entry
    return
  end

  -- Split the actions only, never the `ALTER TABLE <name>` prefix: the first action
  -- would otherwise still carry it and its leading word would read as a column name.
  local actions = (stmt:sub(pos):gsub(';%s*$', ''))
  for _, action in ipairs(split_commas(actions)) do
    local upper = action:upper()
    local col, rest = action:match('[Cc][Oo][Ll][Uu][Mm][Nn]%s+"?([%w_]+)"?%s*(.*)$')
    if not col then
      -- `ADD`/`DROP` may omit the COLUMN keyword; a constraint entry must not pass.
      if upper:match('^ADD%f[%W]') or upper:match('^DROP%f[%W]') then
        col, rest = action:match('^%a+%s+"?([%w_]+)"?%s*(.*)$')
        if col and CONSTRAINTS[col:upper()] then col = nil end
      end
    end
    if col then
      if upper:find('%f[%w]DROP%f[%W]') then
        for k = #entry.cols, 1, -1 do
          if entry.cols[k].name:lower() == col:lower() then table.remove(entry.cols, k) end
        end
      elseif upper:find('%f[%w]RENAME%f[%W]') then
        local to = rest:match('^[Tt][Oo]%s+"?([%w_]+)"?')
        for _, c in ipairs(entry.cols) do
          if c.name:lower() == col:lower() and to then c.name = to end
        end
      elseif upper:find('%f[%w]ADD%f[%W]') then
        local col_type = base_type(rest)
        local existing
        for _, c in ipairs(entry.cols) do
          if c.name:lower() == col:lower() then existing = c end
        end
        if existing then
          existing.type, existing.decl = col_type, rest
        else
          entry.cols[#entry.cols + 1] = { name = col, type = col_type, decl = rest }
        end
      elseif upper:find('%f[%w]TYPE%f[%W]') then
        for _, c in ipairs(entry.cols) do
          if c.name:lower() == col:lower() then
            local retyped = (rest:gsub('^[Tt][Yy][Pp][Ee]%s+', ''))
            c.type, c.decl = base_type(retyped), retyped
          end
        end
      end
    end
  end
end

-- CREATE TYPE name AS ENUM (...) / AS (...) - enum labels are worth showing whole.
local function parse_type(index, lines, i, file)
  local stmt = statement(lines, i, 100)
  local at = stmt:upper():find('%f[%w]TYPE%f[%W]')
  if not at then return end
  local name, pos = name_after(stmt, at + #'TYPE')
  if not name then return end

  local def = vim.trim((stmt:sub(pos):gsub(';%s*$', '')))
  keep_doc(index.types, name:lower(), {
    kind = 'type',
    name = name,
    def = def,
    doc = comment_above(lines, i),
    doc_file = file,
    file = file,
    lnum = i,
  })
end

-- ALTER TYPE name { RENAME TO new | ADD VALUE 'label' } - enums grow a label at a time.
local function parse_alter_type(index, lines, i, file)
  local stmt = strip_if_exists(statement(lines, i, 40))
  local at = stmt:upper():find('%f[%w]TYPE%f[%W]')
  if not at then return end
  local name, pos = name_after(stmt, at + #'TYPE')
  local entry = name and index.types[name:lower()]
  if not entry then return end

  local rest = stmt:sub(pos)
  local renamed = rest:match('^%s*[Rr][Ee][Nn][Aa][Mm][Ee]%s+[Tt][Oo]%s+"?([%w_]+)"?')
  if renamed then
    index.types[name:lower()] = nil
    entry.name, entry.file, entry.lnum = renamed, file, i
    index.types[renamed:lower()] = entry
    return
  end

  local label = rest:match("[Aa][Dd][Dd]%s+[Vv][Aa][Ll][Uu][Ee]%s+'([^']*)'")
  local body = entry.def and entry.def:match("[Ee][Nn][Uu][Mm]%s*%((.*)%)%s*$")
  if not label or not body then return end

  local labels = {}
  for existing in body:gmatch("'([^']*)'") do
    if existing == label then return end -- already present
    labels[#labels + 1] = existing
  end

  -- `BEFORE 'x'` / `AFTER 'x'` place the label; enum order is the sort order, so
  -- appending a value that was declared to go first would misreport the type.
  local anchor, after = rest:match("[Bb][Ee][Ff][Oo][Rr][Ee]%s+'([^']*)'"), false
  if not anchor then
    anchor = rest:match("[Aa][Ff][Tt][Ee][Rr]%s+'([^']*)'")
    after = anchor ~= nil
  end
  local slot = #labels + 1
  if anchor then
    for n, existing in ipairs(labels) do
      if existing == anchor then
        slot = after and n + 1 or n
        break
      end
    end
  end
  table.insert(labels, slot, label)

  entry.def = ("AS ENUM ('%s')"):format(table.concat(labels, "', '"))
  entry.file, entry.lnum = file, i
end

-- CREATE [MATERIALIZED] VIEW name AS SELECT ... - indexed by name only; deriving
-- the output columns would mean resolving the whole SELECT.
local function parse_view(index, lines, i, file)
  local stmt = strip_if_exists(statement(lines, i, 200))
  local at = stmt:upper():find('%f[%w]VIEW%f[%W]')
  if not at then return end
  local name = name_after(stmt, at + #'VIEW')
  if not name then return end

  keep_doc(index.tables, name:lower(), {
    kind = stmt:upper():find('%f[%w]MATERIALIZED%f[%W]') and 'materialized view' or 'view',
    name = name,
    cols = {},
    doc = comment_above(lines, i),
    doc_file = file,
    file = file,
    lnum = i,
  })
end

-- DROP marks rather than deletes: a migration that drops a function only to recreate
-- it below is the usual way to change a signature, and the recreate must still inherit
-- the original description. Entries still marked when the scan ends are really gone.
local DROP_KINDS = {
  { pattern = '^DROP%s+FUNCTION%f[%W]', keyword = 'FUNCTION', store = 'functions' },
  { pattern = '^DROP%s+PROCEDURE%f[%W]', keyword = 'PROCEDURE', store = 'functions' },
  { pattern = '^DROP%s+MATERIALIZED%s+VIEW%f[%W]', keyword = 'VIEW', store = 'tables' },
  { pattern = '^DROP%s+TABLE%f[%W]', keyword = 'TABLE', store = 'tables' },
  { pattern = '^DROP%s+VIEW%f[%W]', keyword = 'VIEW', store = 'tables' },
  { pattern = '^DROP%s+TYPE%f[%W]', keyword = 'TYPE', store = 'types' },
}

local function parse_drop(index, lines, i)
  local stmt = strip_if_exists(statement(lines, i, 20))
  local upper = vim.trim(stmt):upper()
  for _, kind in ipairs(DROP_KINDS) do
    if upper:match(kind.pattern) then
      local at = upper:find('%f[%w]' .. kind.keyword .. '%f[%W]')
      local rest = (vim.trim(stmt):sub(at + #kind.keyword):gsub(';.*$', ''))
      -- `DROP TABLE a, b` names several; an argument list stays inside its parens.
      for _, item in ipairs(split_commas(rest)) do
        local name = item:match('^%s*"?([%w_%.]+)')
        local entry = name and index[kind.store][name:lower()]
        if entry then entry.dropped = true end
      end
      return
    end
  end
end

-- scanning --------------------------------------------------------------------

local function scan_file(index, path, label)
  local ok, lines = pcall(vim.fn.readfile, path, '', MAX_LINES)
  if not ok then return end

  for i, line in ipairs(lines) do
    -- Collapse the optional keyword run so dispatch is a plain prefix match: anchoring
    -- keeps `CREATE TRIGGER ... EXECUTE FUNCTION f()` from reading as a declaration.
    local head = line:upper():gsub('^%s+', '')
    head = head:gsub('^CREATE%s+OR%s+REPLACE%s+', 'CREATE ')
    head = head:gsub('^CREATE%s+TEMPORARY%s+', 'CREATE '):gsub('^CREATE%s+TEMP%s+', 'CREATE ')
    head = head:gsub('^CREATE%s+MATERIALIZED%s+', 'CREATE ')

    if head:match('^CREATE%s+FUNCTION%f[%W]') or head:match('^CREATE%s+PROCEDURE%f[%W]') then
      parse_function(index, lines, i, label)
    elseif head:match('^CREATE%s+TABLE%f[%W]') then
      parse_table(index, lines, i, label)
    elseif head:match('^CREATE%s+VIEW%f[%W]') then
      parse_view(index, lines, i, label)
    elseif head:match('^CREATE%s+TYPE%f[%W]') then
      parse_type(index, lines, i, label)
    elseif head:match('^ALTER%s+TABLE%f[%W]') then
      parse_alter_table(index, lines, i, label)
    elseif head:match('^ALTER%s+TYPE%f[%W]') then
      parse_alter_type(index, lines, i, label)
    elseif head:match('^COMMENT%s+ON%f[%W]') then
      parse_comment_on(index, lines, i, label)
    elseif head:match('^DROP%f[%W]') then
      parse_drop(index, lines, i)
    end
  end
end

-- Migrations dir for a root: the first of DIRS that exists, or an explicit override.
local function migrations_dir(root)
  local override = vim.g.sql_docs_migrations
  if override and override ~= '' then
    local path = override:sub(1, 1) == '/' and override or (root .. '/' .. override)
    return vim.fn.isdirectory(path) == 1 and path or nil
  end
  for _, dir in ipairs(DIRS) do
    local path = root .. '/' .. dir
    if vim.fn.isdirectory(path) == 1 then return path end
  end
end

local function build(root)
  local dir = migrations_dir(root)
  if not dir then return nil end

  local files = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == 'file' and name:lower():match('%.sql$') then files[#files + 1] = name end
  end
  if #files == 0 then return nil end
  -- sqlx names migrations by timestamp, so name order is apply order and the last
  -- CREATE OR REPLACE of a function is the one actually running.
  table.sort(files)

  local index = { functions = {}, tables = {}, types = {}, dir = dir, count = 0 }
  local rel = vim.fn.fnamemodify(dir, ':t')
  for n, name in ipairs(files) do
    if n > MAX_FILES then break end
    scan_file(index, dir .. '/' .. name, rel .. '/' .. name)
    index.count = n
  end

  -- Whatever a DROP marked and no later CREATE brought back is gone from the schema.
  for _, store in ipairs({ index.functions, index.tables, index.types }) do
    for key, entry in pairs(store) do
      if entry.dropped then store[key] = nil end
    end
  end
  return index
end

-- public ----------------------------------------------------------------------

local cache = {} -- project root -> index (false when the project has no migrations)

function M.for_buf(bufnr)
  -- Scratch buffers (the dbee editor, a `:new` query pad) have no path to walk up from.
  -- The config keeps one global cwd for the whole session, so it names the same project.
  local root = utils.project_root(bufnr or 0)
      or vim.fs.root(vim.fn.getcwd(), utils.project_root_markers)
      or vim.fn.getcwd()
  if not root then return nil end
  if cache[root] == nil then cache[root] = build(root) or false end
  return cache[root] or nil
end

-- Entry for `name`, or nil. Schema-qualified names fall back to the bare name.
function M.lookup(bufnr, name)
  local index = M.for_buf(bufnr)
  if not index then return nil end
  local key = name:lower()
  local bare = key:match('([^%.]+)$')
  return index.functions[key] or index.tables[key] or index.types[key]
      or index.functions[bare] or index.tables[bare] or index.types[bare]
end

-- Column entry for `table.column`, or nil.
function M.lookup_column(bufnr, table_name, column)
  local index = M.for_buf(bufnr)
  local entry = index and index.tables[table_name:lower()]
  if not entry or not entry.cols then return nil end
  for _, c in ipairs(entry.cols) do
    if c.name:lower() == column:lower() then return c, entry end
  end
end

-- Every `{ table, col }` whose column is named `column`, for resolving a bare name.
function M.columns_named(bufnr, column)
  local idx = M.for_buf(bufnr)
  if not idx then return nil end
  local hits = {}
  for _, entry in pairs(idx.tables) do
    for _, c in ipairs(entry.cols or {}) do
      if c.name:lower() == column:lower() then hits[#hits + 1] = { table = entry, col = c } end
    end
  end
  table.sort(hits, function(a, b) return a.table.name < b.table.name end)
  return hits
end

function M.clear(root)
  if root then cache[root] = nil else cache = {} end
end

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '*.sql',
  callback = function(args) M.clear(utils.project_root(args.buf)) end,
})

vim.api.nvim_create_user_command('SqlDocsReload', function()
  M.clear()
  local index = M.for_buf(0)
  if not index then
    vim.notify('No migrations directory for this project', vim.log.levels.WARN)
    return
  end
  vim.notify(('SQL docs: %d files, %d functions, %d tables, %d types (%s)'):format(
    index.count, vim.tbl_count(index.functions), vim.tbl_count(index.tables),
    vim.tbl_count(index.types), vim.fn.fnamemodify(index.dir, ':~:.')))
end, { desc = 'Rebuild the SQL migration index' })

return M
