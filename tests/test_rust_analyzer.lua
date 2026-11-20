-- rust-analyzer as plugins/lsp.lua sets it up through rustaceanvim, run for
-- real on a throwaway crate. Skipped where rust-analyzer is not installed.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-cmp', 'cmp-nvim-lsp', 'nvim-lspconfig', 'rustaceanvim' } })
      child.lua([[require('plugins.lsp')]])
    end,
    post_once = child.stop,
  },
})

-- Open src/lib.rs of a crate made of `lines` and wait for rust-analyzer.
local function open_crate(lines)
  if vim.fn.executable('rust-analyzer') == 0 then MiniTest.skip('rust-analyzer is not installed') end
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/src', 'p')
  dir = vim.uv.fs_realpath(dir) or dir
  vim.fn.writefile({ '[package]', 'name = "crate"', 'version = "0.1.0"', 'edition = "2021"' }, dir .. '/Cargo.toml')
  vim.fn.writefile(lines, dir .. '/src/lib.rs')
  child.lua([[
    local dir = ...
    vim.cmd.cd(dir)
    vim.cmd.edit(dir .. '/src/lib.rs')
    vim.wait(30000, function() return #vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' }) > 0 end, 50)
  ]], { dir })
end

-- Workspace symbols rust-analyzer finds for `query`, once it has indexed any.
local function symbol_count(query)
  return child.lua([[
    local query, n = ..., 0
    vim.wait(30000, function()
      n = 0
      local res = vim.lsp.buf_request_sync(0, 'workspace/symbol', { query = query }, 10000)
      for _, r in pairs(res or {}) do n = n + #(r.result or {}) end
      return n > 0
    end, 100)
    return n
  ]], { query })
end

-- Before d60b55c, a type search (<leader>ft) stopped at rust-analyzer's default
-- of 128 results, so in a big workspace the type sought could be cut off.
T['a type search returns every matching type'] = function()
  local lines = {}
  for i = 1, 150 do lines[i] = ('pub struct Type%03d;'):format(i) end
  open_crate(lines)
  eq(symbol_count('Type'), 150)
end

return T
