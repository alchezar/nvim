-- LSP hover against a fake server. Long fn signatures break one param per
-- line, and the side panel stacks the type's hover under the field's.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

-- Hover lines for a server whose hover is the rust code block `signature`.
local function hover(signature)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'fn main() {}' })
  child.cmd('noautocmd setlocal filetype=rust')
  H.start_fake_lsp(child, {
    ['textDocument/hover'] = {
      contents = { kind = 'markdown', value = '```rust\n' .. signature .. '\n```' },
    },
  }, { hoverProvider = true })
  return child.lua([[
    local got
    require('config.utils').hover_lines(0, function(lines) got = lines end)
    vim.wait(2000, function() return got ~= nil end)
    return got
  ]])
end

local function wrap(lines)
  return vim.list_extend(vim.list_extend({ '```rust' }, lines), { '```' })
end

T['splits params one per line'] = function()
  eq(hover('fn add(a: i32, b: i32) -> i32'),
    wrap({ 'fn add(', '    a: i32,', '    b: i32,', ') -> i32' }))
end

T['keeps generics and tuples whole'] = function()
  eq(hover('fn f(a: Result<T, E>, b: (u8, u8))'),
    wrap({ 'fn f(', '    a: Result<T, E>,', '    b: (u8, u8),', ')' }))
end

T['leaves a single param alone'] = function()
  eq(hover('fn one(a: u32) -> u32'), wrap({ 'fn one(a: u32) -> u32' }))
end

-- Before 2b05ae4, the first `(` on the line was taken as the param list, so
-- `pub(crate)` and a `Fn(..)` bound broke the split.
T['finds params past pub(crate)'] = function()
  eq(hover('pub(crate) fn connect(url: &str, retries: u32) -> Pool'),
    wrap({ 'pub(crate) fn connect(', '    url: &str,', '    retries: u32,', ') -> Pool' }))
end

T['finds params past a generic Fn bound'] = function()
  eq(hover('fn apply<F: Fn(u32) -> u32>(f: F, x: u32) -> u32'),
    wrap({ 'fn apply<F: Fn(u32) -> u32>(', '    f: F,', '    x: u32,', ') -> u32' }))
end

-- Hover panel for a field whose type lives in another file: the field's hover,
-- then the type's below a red divider. Returns panel text and type sections.
local function panel(own, type_doc)
  local file = vim.fn.tempname() .. '.rs'
  vim.fn.writefile({ 'let s = order.status;' }, file)
  child.cmd('edit ' .. file)
  child.cmd('noautocmd setlocal filetype=rust')
  local md = function(v) return { contents = { kind = 'markdown', value = v } } end
  local types_uri = 'file:///tmp/types.rs'
  H.start_fake_lsp(child, {
    ['textDocument/hover'] = md(own),
    ['textDocument/typeDefinition'] = {
      { uri = types_uri, range = { start = { line = 3, character = 9 }, ['end'] = { line = 3, character = 15 } } },
    },
    ['textDocument/hover ' .. types_uri .. ':3'] = md(type_doc),
  }, { hoverProvider = true, typeDefinitionProvider = true })
  return child.lua([[
    local utils = require('config.utils')
    local orig, done = utils.type_hovers, false
    utils.type_hovers = function(win, cb)
      orig(win, function(docs) cb(docs); done = true end)
    end
    require('custom.side_panel').open()
    vim.wait(2000, function() return done end)
    local pbuf
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'HoverPanel' then pbuf = b end
    end
    local ns = vim.api.nvim_get_namespaces().hover_panel
    local sections = 0
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(pbuf, ns, 0, -1, { details = true })) do
      if m[4].hl_group == 'HoverPanelTypeDivider' then sections = sections + 1 end
    end
    return { table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), '\n'), sections }
  ]])
end

local STATUS = '```rust\nshop\n```\n\n```rust\nenum Status\n```\n\n---\n\nOrder state.'

T['panel shows the type below the field'] = function()
  local text, sections = unpack(panel('```rust\nshop::Order\n```\n\n```rust\nstatus: Status\n```', STATUS))
  eq({ sections, text:find('status: Status', 1, true) ~= nil, text:find('enum Status', 1, true) ~= nil },
    { 1, true, true })
end

-- Before e75f308, on the type's own name the type's hover repeated the
-- cursor's.
T['panel skips the type when it is the cursor'] = function()
  local text, sections = unpack(panel(STATUS, STATUS))
  local _, count = text:gsub('enum Status', '')
  eq({ sections, count }, { 0, 1 })
end

T['the hover float puts line diagnostics above the docs'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'fn main() {}' })
  child.cmd('noautocmd setlocal filetype=rust')
  H.start_fake_lsp(child, { ['textDocument/hover'] = { contents = { kind = 'markdown', value = 'Entry.' } } },
    { hoverProvider = true })
  eq(child.lua([[
    local ns = vim.api.nvim_create_namespace('test')
    vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = 'unused', severity = 2 } })
    require('config.utils').hover()
    local lines
    vim.wait(2000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= '' then
          lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
        end
      end
      return lines ~= nil
    end)
    -- The rule spans the float, sized to its content.
    lines[2] = lines[2]:gsub('\u{2500}', '') == '' and 'RULE' or lines[2]
    return lines
  ]]), { '**[WARN]** unused', 'RULE', 'Entry.' })
end

return T
