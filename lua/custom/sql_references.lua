-- Other uses of the SQL name under the cursor inside an injected query, painted
-- like LSP references. rust-analyzer sees the whole query as one string.

require('custom.lsp_reference_tint')
local Kind = vim.lsp.protocol.DocumentHighlightKind

local M = {}

-- The injected SQL tree root holding row/col, or nil outside one.
local function sql_root(bufnr, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return end
  local got, root = pcall(function()
    parser:parse({ row, row + 1 })
    local lt = parser:language_for_range({ row, col, row, col })
    if not lt or lt:lang() ~= 'sql' then return end
    for _, tree in pairs(lt:trees()) do
      local r = tree:root()
      if vim.treesitter.is_in_node_range(r, row, col) then return r end
    end
  end)
  return got and root or nil
end

-- Name-like tokens between byte columns `from` and `to` (1-based, inclusive) as
-- { start, end, text }. Strings and `--` comments yield none, numbers are skipped.
local function tokens(line, from, to)
  local out, i = {}, from
  while i <= to do
    local c = line:sub(i, i)
    local s, e
    if c == '"' then
      s, e = i, math.min(line:find('"', i + 1, true) or to, to)
    elseif c == "'" then
      i = (line:find("'", i + 1, true) or to) + 1
      goto continue
    elseif line:sub(i, i + 1) == '--' then
      break
    else
      local _, num = line:find('^%d[%w_$]*', i)
      if num then
        i = num + 1
        goto continue
      end
      s, e = line:find('^[%a_][%w_$]*', i)
      if not s then s, e = line:find('^%$%d+', i) end
    end
    if s then
      out[#out + 1] = { s - 1, math.min(e, to), line:sub(s, math.min(e, to)) }
      i = e + 1
    else
      i = i + 1
    end
    ::continue::
  end
  return out
end

-- Unquoted names fold to lower case; a quoted name equals its bare form only when
-- that form would survive folding.
local function norm(text)
  local inner = text:match('^"(.*)"$')
  if inner then return inner:match('^[%l_][%l%d_$]*$') or text end
  return text:lower()
end

-- The token's own node, or nil when it is a keyword, comment or plain literal. ERROR
-- zones drop identifiers from the tree, so a bare word there still counts.
local function name_node(root, row, tok)
  local node = root:named_descendant_for_range(row, tok[1], row, tok[2])
  local t = node:type()
  if t:match('^keyword_') or t == 'comment' or t == 'marginalia' then return end
  if t == 'literal' and tok[3]:sub(1, 1) ~= '"' then return end
  return node
end

-- Definitions and assignment targets are writes, like a `let` to rust-analyzer.
local DEFINES = { cte = true, relation = true, term = true, column = true, column_definition = true }

local function kind_of(node)
  local parent = node:parent()
  if not parent or node:type() ~= 'identifier' then return Kind.Read end
  if DEFINES[parent:type()] then return Kind.Write end
  local grand = parent:parent()
  if parent:type() == 'field' and grand and grand:type() == 'assignment' and grand:named_child(0):equal(parent) then
    return Kind.Write
  end
  return Kind.Read
end

-- Paints the uses when the cursor sits in an injected query. Returns false outside
-- one, so the caller can ask the language server instead.
function M.highlight(bufnr)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local root = sql_root(bufnr, row, col)
  if not root then return false end

  local srow, scol, erow, ecol = root:range()
  local lines = vim.api.nvim_buf_get_lines(bufnr, srow, erow + 1, false)
  local function row_tokens(r)
    local line = lines[r - srow + 1] or ''
    return tokens(line, r == srow and scol + 1 or 1, r == erow and ecol or #line)
  end

  -- In insert mode the cursor rests one past the word it just typed.
  local pad = vim.fn.mode():match('^i') and 1 or 0
  local target
  for _, tok in ipairs(row_tokens(row)) do
    if col >= tok[1] and col < tok[2] + pad and name_node(root, row, tok) then
      target = norm(tok[3])
      break
    end
  end

  local refs = {}
  if target then
    for r = srow, erow do
      for _, tok in ipairs(row_tokens(r)) do
        local node = norm(tok[3]) == target and name_node(root, r, tok)
        if node then
          refs[#refs + 1] = {
            range = { start = { line = r, character = tok[1] }, ['end'] = { line = r, character = tok[2] } },
            kind = kind_of(node),
          }
        end
      end
    end
  end
  vim.lsp.util.buf_highlight_references(bufnr, refs, 'utf-8')
  return true
end

return M
