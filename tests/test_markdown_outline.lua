-- Heading tree of a markdown buffer from custom/markdown_outline.lua, which
-- feeds the <leader>o picker and the outline panel.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function() child.setup() end,
    post_once = child.stop,
  },
})

-- Headings of a buffer of `lines` as `lnum indent text`.
local function outline(lines)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  return child.lua([[
    return vim.tbl_map(function(h)
      return ('%d %d %s'):format(h.lnum, h.indent, h.text)
    end, require('custom.markdown_outline').headings(0))
  ]])
end

T['nesting follows the document even where levels skip'] = function()
  eq(outline({ '# Guide', '### Deep', '## Mid', '#### Leaf', '# Next' }),
    { '1 0 Guide', '2 1 Deep', '3 1 Mid', '4 2 Leaf', '5 0 Next' })
end

T['code fences and front matter hold no headings'] = function()
  eq(outline({
    '---', '# title: not a heading', '---',
    '# Real',
    '````sh', '# a shell comment', '```', '# still code', '````',
    '~~~', '## tilde code', '~~~',
    '## After',
  }), { '4 0 Real', '13 1 After' })
end

T['headings read as plain text'] = function()
  eq(outline({ '# The [docs](https://x.y) and `code` **now** ##', '####### seven', '#tag' }),
    { '1 0 The docs and code now' })
end

return T
