-- markdown_toc in the side panel, checked by screenshot. Covers nesting, the
-- current section's cursorline, a fenced `#` left out and folding.
local new_set = MiniTest.new_set
local expect = MiniTest.expect
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

return T
