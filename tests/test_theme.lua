-- colors/kinder_theme.lua as drawn. Checked by the color and attributes of a
-- screen cell once treesitter and the semantic tokens have painted it.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true, runtime = true })
      child.o.lines, child.o.columns = 10, 60
      child.lua([[
        vim.o.termguicolors = true
        vim.cmd.colorscheme('kinder_theme')
      ]])
    end,
    post_once = child.stop,
  },
})

-- Color and attributes drawn at buffer line `lnum`, byte column `col`.
local function cell(lnum, col)
  return child.lua([[
    vim.cmd('redraw')
    local p = vim.fn.screenpos(0, ...)
    return vim.api.nvim__inspect_cell(1, p.row - 1, p.col - 1)[2]
  ]], { lnum, col })
end

-- A rust buffer of `lines` under treesitter, with rust-analyzer faked to send
-- `data` as its semantic tokens over `legend`.
local function rust(lines, legend, data)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  child.cmd('setlocal filetype=rust')
  child.lua([[vim.treesitter.start(0, 'rust')]])
  H.start_fake_lsp(child, { ['textDocument/semanticTokens/full'] = { data = data } },
    { semanticTokensProvider = { legend = legend, full = true } })
  -- The first token sits at (data[1], data[2]).
  child.lua([[
    local row, col = ...
    vim.wait(2000, function() return #vim.lsp.semantic_tokens.get_at_pos(0, row, col) > 0 end)
  ]], { data[1], data[2] })
end

-- Before 4f701c8, a private field read outside its declaration fell back to
-- the default property color, unlike the same field where it is declared.
T['a private rust field has one color where declared and where read'] = function()
  -- The two `field`s: a declaration, then a plain property, neither declared
  -- nor public.
  rust({ 'struct S { field: u8 }', 'fn f(s: S) -> u8 { s.field }' },
    { tokenTypes = { 'property' }, tokenModifiers = { 'declaration' } },
    { 0, 11, 5, 0, 1, 1, 21, 5, 0, 0 })
  eq(cell(2, 22), cell(1, 12))
end

-- Before ce622a5, a bare word inside an attribute, which rust-analyzer marks
-- generic with the attribute modifier, kept its plain treesitter color.
T['words inside a rust attribute are dimmed like the attribute'] = function()
  -- `derive`, then the `get` argument.
  rust({ '#[derive(Clone)]', '#[utoipa::path(get)]', 'fn f() {}' },
    { tokenTypes = { 'builtinAttribute', 'generic' }, tokenModifiers = { 'attribute' } },
    { 0, 2, 6, 0, 1, 1, 15, 3, 1, 1 })
  eq(cell(2, 16), cell(1, 3))
end

-- Before 44d721a, markdown links fell back to Underlined.
T['a markdown link is drawn in color, not underlined'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'see [the docs](https://example.com)' })
  child.cmd('setlocal filetype=markdown')
  child.lua([[vim.treesitter.start(0, 'markdown')]])
  local c = cell(1, 5)
  eq({ underline = c.underline, colored = c.foreground ~= nil }, { colored = true })
end

return T
