-- plugins/lsp.lua drops rust-analyzer's unused_qualifications hits that have
-- no `::` to remove, which macros like #[utoipa::path] stamp on bare tokens.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-cmp', 'cmp-nvim-lsp', 'nvim-lspconfig' } })
      child.lua([[require('plugins.lsp')]])
    end,
    post_once = child.stop,
  },
})

-- Diagnostics kept after rust-analyzer publishes `ranges` over `lines`.
local function kept(lines, ranges)
  local file = vim.fn.tempname() .. '.rs'
  vim.fn.writefile(lines, file)
  child.cmd('edit ' .. file)
  child.cmd('noautocmd setlocal filetype=')
  H.start_fake_lsp(child, {}, {}, 'rust-analyzer')
  return child.lua([[
    local ranges = ...
    local client = vim.lsp.get_clients({ bufnr = 0, name = 'rust-analyzer' })[1]
    local diags = {}
    for _, r in ipairs(ranges) do
      diags[#diags + 1] = {
        code = 'unused_qualifications', message = 'unnecessary qualification', severity = 2,
        range = { start = { line = r[1], character = r[2] }, ['end'] = { line = r[1], character = r[3] } },
      }
    end
    vim.lsp.handlers['textDocument/publishDiagnostics'](nil,
      { uri = vim.uri_from_bufnr(0), diagnostics = diags }, { client_id = client.id, method = 'textDocument/publishDiagnostics' })
    local out = {}
    for _, d in ipairs(vim.diagnostic.get(0)) do out[#out + 1] = d.lnum .. ':' .. d.col end
    table.sort(out)
    return out
  ]], { ranges })
end

-- Before 5460a12, a hit on a bare token from a macro expansion was shown
-- with nothing to fix.
T['keeps real qualifications, drops macro ghosts'] = function()
  local lines = { '#[utoipa::path(get)]', 'fn f(x: std::fmt::Error) {}' }
  eq(kept(lines, { { 0, 15, 18 }, { 1, 8, 18 } }), { '1:8' })
end

return T
