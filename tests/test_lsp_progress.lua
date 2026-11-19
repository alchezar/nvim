-- custom/neovide_lsp_progress.lua turns LspProgress into Neovide's progress
-- bar through nvim_echo(kind = 'progress'). Neovide is faked with g:neovide
-- and nvim_echo is recorded instead of drawn.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua([[
        vim.g.neovide = true
        _G.bars = {}
        vim.api.nvim_echo = function(chunks, _, opts)
          if opts and opts.kind == 'progress' then
            table.insert(_G.bars, chunks[1][1])
          end
        end
        require('custom.neovide_lsp_progress')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'text' })
      ]])
    end,
    post_once = child.stop,
  },
})

local function progress(kind, title)
  child.lua([[
    local kind, title = ...
    vim.api.nvim_exec_autocmds('LspProgress', {
      data = {
        client_id = 1,
        params = { token = 't', value = { kind = kind, title = title, percentage = 10 } },
      },
    })
  ]], { kind, title })
end

-- Bars drawn since the last call.
local function drawn()
  return child.lua([[
    local out = _G.bars
    _G.bars = {}
    return out
  ]])
end

T['progress shows on the bar'] = function()
  progress('begin', 'Indexing')
  eq(drawn(), { 'Indexing' })
end

-- Before 5affbde, the bar kept drawing in visual mode, where extui stacked it
-- with the mode message and grew the cmdline.
T['visual mode blanks the bar and leaving it brings it back'] = function()
  progress('begin', 'Indexing')
  drawn()
  child.type_keys('v')
  progress('report', 'Indexing')
  local during = drawn()
  child.type_keys('<Esc>')
  eq({ during = during, after = drawn() }, { during = { '' }, after = { 'Indexing' } })
end

return T
