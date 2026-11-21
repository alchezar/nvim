-- Other uses of a SQL name in an sqlx query, from custom/sql_references.lua.
-- rust-analyzer sees the query as one string, so treesitter finds them.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function() child.setup({ treesitter = true }) end,
    post_once = child.stop,
  },
})

-- A rust file whose function runs `sql` through sqlx, opened in the child.
local function query(sql)
  local file = vim.fn.tempname() .. '.rs'
  vim.fn.writefile({ 'fn f() {', '    let r = sqlx::query!(r#"' .. sql .. '"#);', '}' }, file)
  child.cmd('edit ' .. file)
end

-- Puts the cursor `off` bytes into the first `needle`.
local function cursor(needle, off)
  child.lua([[
    local needle, off = ...
    for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      local col = line:find(needle, 1, true)
      if col then return vim.api.nvim_win_set_cursor(0, { row, col - 1 + (off or 0) }) end
    end
    error('needle not found: ' .. needle)
  ]], { needle, off })
end

-- Painted uses as `text kind`, in buffer order.
local function marks()
  return child.lua([[
    local ns = vim.api.nvim_get_namespaces()['nvim.lsp.references']
    local out = {}
    for _, m in ipairs(ns and vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true }) or {}) do
      local text = vim.api.nvim_buf_get_text(0, m[2], m[3], m[2], m[4].end_col, {})[1]
      out[#out + 1] = text .. ' ' .. (m[4].hl_group:match('Write') and 'write' or 'read')
    end
    return out
  ]])
end

-- Highlights from the cursor on `needle`; returns what the call reported too.
local function highlight(needle, off)
  cursor(needle, off)
  local inside = child.lua_get([[require('custom.sql_references').highlight(0)]])
  return { inside = inside, marks = marks() }
end

T['a name lights up at every use in its query'] = function()
  query('SELECT id FROM users WHERE id = $1 OR $1 IS NULL')
  eq({ highlight('id FROM').marks, highlight('$1').marks },
    { { 'id read', 'id read' }, { '$1 read', '$1 read' } })
end

T['a definition or assignment target is a write'] = function()
  query('WITH x AS (SELECT 1) UPDATE t SET n = n + 1 FROM x WHERE n > 0')
  eq({ highlight('x AS').marks, highlight('n =').marks },
    { { 'x write', 'x read' }, { 'n write', 'n read', 'n read' } })
end

T['an alias is defined where it follows its table'] = function()
  query('SELECT u.id FROM users u WHERE u.id = 1')
  eq(highlight('u.id').marks, { 'u read', 'u write', 'u read' })
end

T['names fold case unless quoted'] = function()
  query('SELECT "id", ID, "Id" FROM t WHERE id = 1')
  eq({ highlight('ID').marks, highlight('"Id"').marks },
    { { '"id" read', 'ID read', 'id read' }, { '"Id" read' } })
end

T['keywords, numbers and strings mark nothing'] = function()
  query("SELECT 1 FROM t WHERE name = 'name'")
  eq({ highlight('SELECT').marks, highlight('1').marks, highlight('name =').marks },
    { {}, {}, { 'name read' } })
end

T['outside a query it leaves the word to the language server'] = function()
  query('SELECT id FROM t')
  eq(highlight('let'), { inside = false, marks = {} })
end

-- Wired in plugins/lsp.lua: resting in a query paints the SQL uses instead of
-- what the server would answer for the whole string.
T['resting in a query paints sql uses, not the server answer'] = function()
  child.setup({ treesitter = true, plugins = { 'nvim-cmp', 'cmp-nvim-lsp', 'nvim-lspconfig' } })
  child.lua([[require('plugins.lsp')]])
  query('SELECT id FROM t WHERE id = 1')
  local whole = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 7 } }
  H.start_fake_lsp(child, { ['textDocument/documentHighlight'] = { { range = whole, kind = 1 } } },
    { documentHighlightProvider = true })
  cursor('id FROM')
  child.cmd('doautocmd CursorHold')
  local sql = marks()
  cursor('let')
  child.cmd('doautocmd CursorHold')
  child.lua([[vim.wait(500, function()
    return #vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()['nvim.lsp.references'], 0, -1, {}) > 0
  end)]])
  eq({ sql, marks() }, { { 'id read', 'id read' }, { 'let read' } })
end

return T
