-- Rustaceanvim config (auto-configures rust-analyzer)
vim.g.rustaceanvim = {
  server = {
    settings = {
      ['rust-analyzer'] = {
        checkOnSave = true,
        check = { command = 'clippy' },
        cargo = { allFeatures = true },
        semanticHighlighting = {
          strings = { enable = false },
        },
        inlayHints = {
          chainingHints = { enable = false },
        },
        lens = {
          enable = true,
          references = { adt = { enable = true }, enumVariant = { enable = true }, method = { enable = true }, trait = { enable = true } },
        },
      },
    },
  },
}

-- Default capabilities for all LSP servers (extends core with cmp_nvim_lsp)
vim.lsp.config('*', {
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})

-- TypeScript / JavaScript
local ts_inlay_hints = {
  includeInlayParameterNameHints = 'all',
  includeInlayFunctionParameterTypeHints = true,
  includeInlayVariableTypeHints = true,
  includeInlayPropertyDeclarationTypeHints = true,
  includeInlayFunctionLikeReturnTypeHints = true,
  includeInlayEnumMemberValueHints = true,
}
vim.lsp.config('ts_ls', {
  settings = {
    typescript = { inlayHints = ts_inlay_hints },
    javascript = { inlayHints = ts_inlay_hints },
  },
})
vim.lsp.enable('ts_ls')

-- ESLint
vim.lsp.config('eslint', {
  settings = {
    workingDirectories = { mode = 'auto' },
  },
})
vim.lsp.enable('eslint')

-- C / C++
vim.lsp.config('clangd', {
  cmd = {
    'clangd',
    '--background-index',
    '--clang-tidy',
    '--header-insertion=iwyu',
    '--completion-style=detailed',
    '--function-arg-placeholders',
    '--fallback-style=llvm',
  },
})
vim.lsp.enable('clangd')

-- Enable code lenses
vim.lsp.codelens.enable(true)

-- Highlight separator lines in hover/float windows
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(args)
    if vim.api.nvim_win_get_config(0).relative ~= '' then
      vim.fn.matchadd('FloatBorder', '^─\\+$')
      vim.fn.matchadd('Comment', '\\v(\\w+::)+')
    end
  end,
})

-- Diagnostic signs
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = true,
  float = { border = 'rounded', source = true },
})
