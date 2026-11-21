-- The right-hand hover panel (custom/hover_panel.lua) in the split it shares
-- with the markdown outline (custom/side_panel.lua), fed by a fake server.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true })
      child.o.lines, child.o.columns = 30, 120
    end,
    post_once = child.stop,
  },
})

-- A rust file of `lines` whose hover on line N (0-based) is `hovers[N + 1]`,
-- a markdown string, or nothing when that entry is false.
local function rust(lines, hovers)
  local tmp = vim.fn.tempname() .. '.rs'
  vim.fn.writefile(lines, tmp)
  -- The server is asked by the resolved path, /private/var on macOS.
  local file = assert(vim.uv.fs_realpath(tmp))
  child.cmd('edit ' .. file)
  local uri = vim.uri_from_fname(file)
  -- An empty hover stands for none; a null would not survive the trip.
  local function reply(md) return { contents = { kind = 'markdown', value = md or '' } } end
  local responses = { ['textDocument/hover'] = reply() }
  for i, md in ipairs(hovers) do
    responses['textDocument/hover ' .. uri .. ':' .. (i - 1)] = reply(md)
  end
  H.start_fake_lsp(child, responses, { hoverProvider = true })
  return file
end

-- Panel text once it holds `needle`, or as it stands after a second.
local function panel(needle)
  return child.lua([[
    local needle = ...
    local function text()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.bo[b].filetype == 'HoverPanel' then
          return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), '\n')
        end
      end
      return ''
    end
    vim.wait(1000, function() return text():find(needle, 1, true) ~= nil end)
    return text()
  ]], { needle })
end

-- Filetypes of the panel split and how many windows the tab holds.
local function layout()
  return child.lua([[
    local fts = {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
      if ft == 'HoverPanel' or ft == 'MarkdownToc' then fts[#fts + 1] = ft end
    end
    return { panel = fts, wins = #vim.api.nvim_tabpage_list_wins(0) }
  ]])
end

local function open_panel()
  child.lua([[require('custom.side_panel').open()]])
end

T['opens beside the editor, keeps focus there and follows the cursor'] = function()
  local file = rust({ 'fn one() {}', 'fn two() {}' }, { 'first doc', 'second doc' })
  open_panel()
  eq({ panel('first doc'), child.api.nvim_buf_get_name(0) }, { 'first doc', file })
  child.type_keys('j')
  eq(panel('second doc'), 'second doc')
end

T['diagnostics of the line come first'] = function()
  rust({ 'fn one() {}' }, { 'the doc' })
  child.lua([[
    local ns = vim.api.nvim_create_namespace('test')
    vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = 'unused', severity = 1, source = 'rustc' } })
  ]])
  open_panel()
  local rule = ('\u{2500}'):rep(40)
  eq(panel('the doc'), '**[ERROR]** (rustc) unused\n' .. rule .. '\nthe doc')
end

T['a diagnostic that lands later still shows up'] = function()
  rust({ 'fn one() {}' }, { 'the doc' })
  open_panel()
  panel('the doc')
  child.lua([[
    local ns = vim.api.nvim_create_namespace('test')
    vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = 'late', severity = 2 } })
  ]])
  eq(panel('late'):match('^[^\n]*'), '**[WARN]** late')
end

T['nothing to hover shows what the file is about'] = function()
  rust({ '//! Parses orders.', '', 'fn one() {}' }, { false, false, 'fn doc' })
  child.cmd('2')
  open_panel()
  eq(panel('Parses orders.'), 'Parses orders.')
end

T['links keep their label, not the url'] = function()
  rust({ 'fn one() {}' }, { 'see [Vec](https://doc.rust-lang.org/std/vec/struct.Vec.html) here' })
  open_panel()
  eq(panel('see'), 'see [Vec] here')
end

T['its prose is grayed like the hover float'] = function()
  rust({ 'fn one() {}' }, { 'the doc' })
  open_panel()
  panel('the doc')
  eq(child.lua([[
    local ns = vim.api.nvim_get_namespaces().hover_panel
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'HoverPanel' then
        local groups = {}
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })) do
          groups[#groups + 1] = m[4].hl_group
        end
        return groups
      end
    end
  ]]), { 'HoverProse' })
end

T['a window that only borrows focus keeps the last hover'] = function()
  rust({ 'fn one() {}', 'fn two() {}' }, { 'first doc', 'second doc' })
  open_panel()
  panel('first doc')
  child.lua([[
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { 'a', 'b' })
    vim.api.nvim_open_win(scratch, true, { relative = 'editor', row = 1, col = 1, width = 10, height = 2 })
  ]])
  child.type_keys('j')
  child.lua('vim.wait(300)')
  eq(panel('second doc'), 'first doc')
end

T['a markdown file swaps the split to its outline and back'] = function()
  local file = rust({ 'fn one() {}' }, { 'the doc' })
  open_panel()
  panel('the doc')
  local md = vim.fn.tempname() .. '.md'
  vim.fn.writefile({ '# Title', '', '## Part' }, md)
  child.cmd('edit ' .. md)
  child.lua('vim.wait(200)')
  local in_md = layout()
  child.cmd('edit ' .. file)
  child.lua('vim.wait(200)')
  eq({ in_md, layout() }, {
    { panel = { 'MarkdownToc' }, wins = 2 },
    { panel = { 'HoverPanel' },  wins = 2 },
  })
end

T['q in the panel and the toggle both close it'] = function()
  rust({ 'fn one() {}' }, { 'the doc' })
  open_panel()
  panel('the doc')
  child.cmd('wincmd l')
  child.type_keys('q')
  local after_q = layout()
  child.lua([[require('custom.side_panel').toggle()]])
  local reopened = layout()
  child.lua([[require('custom.side_panel').toggle()]])
  eq({ after_q, reopened, layout() }, {
    { panel = {},               wins = 1 },
    { panel = { 'HoverPanel' }, wins = 2 },
    { panel = {},               wins = 1 },
  })
end

return T
