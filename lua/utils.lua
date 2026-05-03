local M = {}

-- Open yazi file manager and edit the chosen file
function M.open_yazi()
  local tmp = vim.fn.tempname()
  vim.cmd('silent !yazi --chooser-file=' .. tmp)
  vim.cmd('redraw!')
  local f = io.open(tmp, 'r')
  if not f then return end
  local path = f:read('*l')
  f:close()
  os.remove(tmp)
  if path and path ~= '' then
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
  end
end

-- Switch between C/C++ source and header file via clangd
function M.switch_source_header()
  local clients = vim.lsp.get_clients({ bufnr = 0, name = 'clangd' })
  if #clients == 0 then
    vim.notify('clangd not attached', vim.log.levels.WARN)
    return
  end
  clients[1]:request('textDocument/switchSourceHeader',
    vim.lsp.util.make_text_document_params(0),
    function(err, result)
      if err then
        vim.notify('switchSourceHeader: ' .. tostring(err), vim.log.levels.ERROR)
        return
      end
      if not result then
        vim.notify('No matching source/header file', vim.log.levels.INFO)
        return
      end
      vim.cmd.edit(vim.uri_to_fname(result))
    end, 0)
end

-- Toggle LSP inlay hints
function M.toggle_inlay_hints()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end

-- LSP hover with limited width
function M.hover()
  vim.lsp.buf.hover({ max_width = 80 })
end

-- Format current buffer via conform.nvim
function M.format()
  require('conform').format({ async = true, lsp_format = 'fallback' })
end

-- Project root markers used to auto-cd into the project of the current buffer
M.project_root_markers = {
  '.git',
  'CMakeLists.txt',
  'Cargo.lock',
  'package.json',
  'pyproject.toml',
  'go.mod',
  '.clangd',
  'compile_commands.json',
}

-- Auto-cd to the detected project root when entering a buffer
function M.auto_cd_to_project_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.bo[bufnr].buftype ~= '' then return end
  local root = vim.fs.root(bufnr, M.project_root_markers)
  if root and root ~= vim.fn.getcwd() then
    vim.cmd.lcd(root)
  end
end

return M
