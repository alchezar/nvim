require('conform').setup({
  formatters_by_ft = {
    typescript      = { 'prettier' },
    typescriptreact = { 'prettier' },
    javascript      = { 'prettier' },
    javascriptreact = { 'prettier' },
    json            = { 'prettier' },
    jsonc           = { 'prettier' },
    css             = { 'prettier' },
    scss            = { 'prettier' },
    html            = { 'prettier' },
    markdown        = { 'prettier' },
    yaml            = { 'prettier' },
    cpp             = { 'clang_format' },
    c               = { 'clang_format' },
    python          = { 'ruff_organize_imports', 'ruff_format' },
  },
  format_on_save = {
    timeout_ms = 1000,
    lsp_format = 'fallback',
  },
})
