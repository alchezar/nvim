-- utils.restart_buf_lsp (<leader>rl) against a fake server. A buffer whose
-- server died gets one again, and a restart wipes its stale diagnostics.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      -- FileType attaches the server, the way vim.lsp.enable() does.
      child.lua([[
        vim.api.nvim_create_autocmd('FileType', {
          pattern = 'faketype',
          callback = function()
            if _G.fake_lsp_cmd then
              vim.lsp.start({ name = 'fake', cmd = _G.fake_lsp_cmd, root_dir = vim.fn.getcwd() })
            end
          end,
        })
      ]])
    end,
    post_once = child.stop,
  },
})

local function edit(name)
  child.cmd('edit ' .. vim.fn.tempname() .. name)
  child.cmd('noautocmd setlocal filetype=faketype')
end

local function clients()
  return child.lua_get([[#vim.lsp.get_clients({ bufnr = 0, name = 'fake' })]])
end

-- Before 0cd17b2, a buffer left with no client only got a warning.
T['a buffer with no client gets one again'] = function()
  edit('a.txt')
  H.start_fake_lsp(child, {}, {})
  child.lua([[
    vim.lsp.get_clients({ bufnr = 0 })[1]:stop(true)
    vim.wait(2000, function() return #vim.lsp.get_clients({ bufnr = 0 }) == 0 end)
  ]])
  eq(clients(), 0)
  child.lua([[require('config.utils').restart_buf_lsp()]])
  eq(child.lua_get([[vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = 0, name = 'fake' }) > 0
  end)]]), true)
end

-- Before 69f194d, only the current buffer's diagnostics were reset. Files the
-- server reported on without them being open kept errors it no longer sees.
T['restart clears stale diagnostics of files not open'] = function()
  edit('a.txt')
  H.start_fake_lsp(child, {}, {})
  local other = child.lua([[
    local client = vim.lsp.get_clients({ name = 'fake' })[1]
    local uri = vim.uri_from_fname(vim.fn.tempname() .. 'b.txt')
    vim.lsp.diagnostic.on_publish_diagnostics(nil, {
      uri = uri,
      diagnostics = { { message = 'stale', severity = 1,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 1 } } } },
    }, { client_id = client.id, method = 'textDocument/publishDiagnostics' })
    return vim.uri_to_bufnr(uri)
  ]])
  eq(child.lua_get('#vim.diagnostic.get(...)', { other }), 1)
  child.lua([[require('config.utils').restart_buf_lsp()]])
  eq(child.lua_get('#vim.diagnostic.get(...)', { other }), 0)
end

return T
