-- markdown_toc in the side panel, checked by screenshot. Covers nesting, the
-- current section's cursorline, a fenced `#` left out and folding.
local new_set = MiniTest.new_set
local expect = MiniTest.expect
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'tests/minimal_init.lua' })
      child.o.lines, child.o.columns = 14, 80
      child.lua([[require('custom.markdown_toc')]])
    end,
    post_once = child.stop,
  },
})

local DOC = {
  '# Guide',
  'Intro.',
  '## Install',
  '### From source',
  'Steps.',
  '## Usage',
  '```sh',
  '# a shell comment, not a heading',
  '```',
  '# Appendix',
}

-- The panel only reads 'filetype'. Skipping the markdown ftplugin keeps its
-- syntax colors, which change between nvim releases, off the screenshot.
local function open_toc(cursor_row)
  child.api.nvim_buf_set_lines(0, 0, -1, false, DOC)
  child.cmd('noautocmd setlocal filetype=markdown')
  child.api.nvim_win_set_cursor(0, { cursor_row, 0 })
  child.cmd('MarkdownToc')
end

T['opens on the current section'] = function()
  open_toc(5) -- 'Steps.' belongs to "From source"
  expect.reference_screenshot(child.get_screenshot())
end

T['Tab folds a section'] = function()
  open_toc(1)
  child.type_keys('<C-w>l', '2G', '<Tab>') -- panel row 2 is "Install"
  expect.reference_screenshot(child.get_screenshot())
end

-- Panel rows, glyphs and indent stripped; {} once the panel is gone.
local function rows()
  return child.lua([[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == 'MarkdownToc' then
        local out = {}
        for _, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
          l = vim.trim((l:gsub('[\128-\255]+', '')))
          if l ~= '' then out[#out + 1] = l end
        end
        return out
      end
    end
    return {}
  ]])
end

-- Focus the panel with its cursor on the row reading `text`.
local function to_row(text)
  child.type_keys('<C-w>l')
  for i, r in ipairs(rows()) do
    if r == text then return child.api.nvim_win_set_cursor(0, { i, 0 }) end
  end
  error('no row ' .. text)
end

T['enter jumps to the heading and returns to the text, o stays'] = function()
  open_toc(1)
  to_row('Usage')
  child.type_keys('o')
  local stayed = child.bo.filetype
  to_row('Appendix')
  child.type_keys('<CR>')
  eq({ stayed, child.bo.filetype, child.api.nvim_win_get_cursor(0)[1] }, { 'MarkdownToc', 'markdown', 10 })
end

T['zM folds every section, zR opens them again'] = function()
  open_toc(1)
  to_row('Guide')
  child.type_keys('zM')
  local folded = rows()
  child.type_keys('zR')
  eq({ folded, #rows() }, { { 'Guide', 'Appendix' }, 5 })
end

T['a heading typed into the text joins the outline'] = function()
  open_toc(1)
  child.api.nvim_buf_set_lines(0, 1, 2, false, { '## Why' })
  child.cmd('doautocmd TextChanged')
  child.lua('vim.wait(400)')
  eq(rows(), { 'Guide', 'Why', 'Install', 'From source', 'Usage', 'Appendix' })
end

-- The split stays open away from markdown; since c0de33e it shows the hover
-- panel there instead of an empty outline.
T['outside markdown the panel empties, and fills again on return'] = function()
  open_toc(1)
  child.cmd('enew')
  child.lua('vim.wait(100)')
  local wins = #child.api.nvim_list_wins()
  local stale = vim.tbl_contains(rows(), 'Guide')
  child.cmd('buffer #')
  child.lua('vim.wait(100)')
  eq({ wins, stale, #rows() }, { 2, false, 5 })
end

T['a single click on a row jumps there'] = function()
  open_toc(1)
  to_row('Usage')
  local pos = child.lua([[
    local w = vim.api.nvim_get_current_win()
    local row, col = unpack(vim.api.nvim_win_get_position(w))
    return { row + vim.api.nvim_win_get_cursor(w)[1] - 1, col + 4 }
  ]])
  child.api.nvim_input_mouse('left', 'press', '', 0, pos[1], pos[2])
  child.api.nvim_input_mouse('left', 'release', '', 0, pos[1], pos[2])
  child.lua('vim.wait(50)')
  eq({ child.bo.filetype, child.api.nvim_win_get_cursor(0)[1] }, { 'markdown', 6 })
end

T['q closes the panel'] = function()
  open_toc(1)
  to_row('Guide')
  child.type_keys('q')
  eq(#child.api.nvim_list_wins(), 1)
end

return T
