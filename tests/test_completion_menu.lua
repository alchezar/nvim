-- nvim-cmp rows from plugins/completion_setup.lua. A long rust-analyzer
-- signature becomes `name(args) -> Ret`, cut short whatever the screen width.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-cmp', 'LuaSnip' } })
      child.o.columns = 200
      child.lua([[require('plugins.completion_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Menu row for an item whose labelDetails are `ld`.
local function row(abbr, ld)
  return child.lua([[
    local abbr, ld = ...
    local entry = { get_completion_item = function() return { labelDetails = ld } end }
    local item = require('cmp').get_config().formatting.format(entry, { abbr = abbr, kind = 'Function' })
    return { abbr = item.abbr, width = vim.fn.strdisplaywidth(item.abbr), menu = item.menu }
  ]], { abbr, ld })
end

T['a fn signature shows from its name on'] = function()
  local got = row('add', { description = 'pub const fn add(a: i32, b: i32) -> i32' })
  eq(got.abbr, 'add(a: i32, b: i32) -> i32')
end

-- Before c98ad12, the cap was half the screen, so on a wide screen one long
-- signature stretched the menu and the docs window overlapped the names.
T['a long signature is cut on a wide screen'] = function()
  local args = {}
  for i = 1, 12 do args[#args + 1] = ('arg%d: Option<String>'):format(i) end
  local got = row('build', { description = 'pub fn build(' .. table.concat(args, ', ') .. ') -> Self' })
  eq(got.width <= 50, true)
end

T['trait origin goes to the menu column'] = function()
  local got = row('fmt', { description = 'fn fmt(&self) -> Result', detail = '(as Display)' })
  eq(got.menu, '(as Display)')
end

-- Real completion in a rust buffer from a fake server answering `items`;
-- the menu is opened on the text `a`.
local function menu(items)
  child.setup({ plugins = { 'nvim-cmp', 'LuaSnip', 'cmp-nvim-lsp' } })
  child.o.lines, child.o.columns = 30, 200
  child.lua([[
    require('plugins.completion_setup')
    require('cmp_nvim_lsp').setup()
    vim.cmd('enew | setfiletype rust')
  ]])
  H.start_fake_lsp(child, { ['textDocument/completion'] = items, ['completionItem/resolve'] = vim.NIL },
    { completionProvider = { resolveProvider = false } })
  child.type_keys('i', 'a', '<C-Space>')
  child.lua([[vim.wait(2000, function() return require('cmp').visible() end)]])
end

local function labels()
  return child.lua([[
    return vim.tbl_map(function(e) return e:get_completion_item().label end, require('cmp').get_entries())
  ]])
end

local K = { Function = 3, Field = 5, Property = 10, Snippet = 15 }

T['fields come first and snippets last'] = function()
  menu({
    { label = 'alpha',  kind = K.Function },
    { label = 'asnip',  kind = K.Snippet, insertText = 'asnip' },
    { label = 'afield', kind = K.Field },
    { label = 'aprop',  kind = K.Property },
  })
  eq(labels(), { 'afield', 'aprop', 'alpha', 'asnip' })
end

local DOC = '```rust\nfn abc(a: u8, b: Vec<(u8, u8)>) -> u8\n```\nDoes it.'

local function selected()
  return child.lua(
  [[local e = require('cmp').get_selected_entry(); return e and e:get_completion_item().label or false]])
end

T['tab moves the selection without typing it, shift-tab goes back'] = function()
  menu({ { label = 'abc', kind = K.Function }, { label = 'alpha', kind = K.Function } })
  child.type_keys('<Tab>', '<Tab>')
  local down = { selected(), child.api.nvim_get_current_line() }
  child.type_keys('<S-Tab>')
  eq({ down, selected() }, { { 'alpha', 'a' }, 'abc' })
end

-- Lines of the markdown docs float beside the menu.
local function docs()
  return child.lua([[
    vim.wait(1000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'markdown' then return true end
      end
    end)
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'markdown' then return vim.api.nvim_buf_get_lines(b, 0, -1, false) end
    end
    return false
  ]])
end

T['docs keep markdown and put each parameter on its own line'] = function()
  menu({ { label = 'abc', kind = K.Function, documentation = { kind = 'markdown', value = DOC } } })
  child.type_keys('<Tab>')
  eq(docs(), { '```rust', 'fn abc(', '    a: u8,', '    b: Vec<(u8, u8)>,', ') -> u8', '```', 'Does it.' })
end

return T
