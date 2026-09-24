-- prettier formats ```md blocks as markdown too. Only those get injected, the inline
-- injection alone costs ~0.6 s on a 1.4 MB file.
local md_blocks = [[
((fenced_code_block (info_string (language) @_lang) (code_fence_content) @injection.content)
  (#any-of? @_lang "md" "markdown")
  (#set! injection.language "markdown"))
]]

-- Rows of each pipe table in markdown lines, as { row, col } where the row's text starts.
local function table_rows(lines)
  local text = table.concat(lines, '\n')
  local parser = vim.treesitter.get_string_parser(text, 'markdown', { injections = { markdown = md_blocks } })
  parser:parse(true)
  local query = vim.treesitter.query.parse('markdown', '(pipe_table) @table')
  local found = {}
  parser:for_each_tree(function(tree, ltree)
    if ltree:lang() ~= 'markdown' then return end
    for _, node in query:iter_captures(tree:root(), text) do
      local rows = {}
      for child in node:iter_children() do
        if child:type():find('^pipe_table_') then rows[#rows + 1] = { child:start() } end
      end
      found[#found + 1] = rows
    end
  end)
  table.sort(found, function(a, b) return a[1][1] < b[1][1] end)
  return found
end

-- prettier pads table cells to line up the pipes. Tables go back as typed, Q aligns them.
local function keep_tables(_, ctx, lines, callback)
  local typed = vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)
  local old, new = table_rows(typed), table_rows(lines)
  -- Tables that do not pair up leave the whole file as typed.
  if #old ~= #new then return callback(nil, typed) end
  local out = vim.list_slice(lines)
  for i, rows in ipairs(new) do
    if #old[i] ~= #rows then return callback(nil, typed) end
    for k, at in ipairs(rows) do
      local was = old[i][k]
      -- Row prefix (indent, `>`) from prettier, so the table stays in its container.
      out[at[1] + 1] = lines[at[1] + 1]:sub(1, at[2]) .. typed[was[1] + 1]:sub(was[2] + 1)
    end
  end
  callback(nil, out)
end

require('conform').setup({
  formatters_by_ft = {
    typescript      = { 'prettier' },
    typescriptreact = { 'prettier' },
    javascript      = { 'prettier' },
    javascriptreact = { 'prettier' },
    vue             = { 'prettier' },
    json            = { 'prettier' },
    jsonc           = { 'prettier' },
    css             = { 'prettier' },
    scss            = { 'prettier' },
    html            = { 'prettier' },
    markdown        = { 'prettier', 'keep_tables' },
    yaml            = { 'prettier' },
    cpp             = { 'clang_format' },
    c               = { 'clang_format' },
    python          = { 'ruff_organize_imports', 'ruff_format' },
  },
  formatters = {
    keep_tables = { format = keep_tables },
  },
  format_on_save = {
    timeout_ms = 1000,
    lsp_format = 'fallback',
  },
})
