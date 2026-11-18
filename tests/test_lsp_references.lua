-- Reference highlight from plugins/lsp.lua against a fake server. Resting on a
-- word paints its uses; the marks stay while the cursor stays on the word.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-cmp', 'cmp-nvim-lsp', 'nvim-lspconfig' } })
      child.lua([[require('custom.lsp_reference_tint'); require('plugins.lsp')]])
      child.api.nvim_buf_set_lines(0, 0, -1, false, { 'total = total + 1', 'other line' })
      local range = function(c1, c2)
        return { start = { line = 0, character = c1 }, ['end'] = { line = 0, character = c2 } }
      end
      H.start_fake_lsp(child, {
        ['textDocument/documentHighlight'] = { { range = range(0, 5), kind = 3 }, { range = range(8, 13), kind = 2 } },
      }, { documentHighlightProvider = true })
    end,
    post_once = child.stop,
  },
})

-- Painted references as `start-end` columns once the request settles.
local function marks()
  return child.lua([[
    local ns = vim.api.nvim_get_namespaces()['nvim.lsp.references']
    vim.wait(500, function() return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) > 0 end)
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
      out[#out + 1] = m[3] .. '-' .. m[4].end_col
    end
    return out
  ]])
end

T['resting on a word paints its uses'] = function()
  child.cmd('doautocmd CursorHold')
  eq(marks(), { '0-5', '8-13' })
end

-- Before 4db6cd6, any cursor move cleared them, so moving inside the word
-- made the highlight blink off until the next CursorHold.
T['moving within the word keeps them, leaving clears'] = function()
  child.cmd('doautocmd CursorHold')
  marks()
  child.type_keys('ll')
  eq(marks(), { '0-5', '8-13' })
  child.type_keys('j')
  eq(child.lua([[
    local ns = vim.api.nvim_get_namespaces()['nvim.lsp.references']
    return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
  ]]), 0)
end

return T
