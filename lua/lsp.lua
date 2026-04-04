-- Rustaceanvim config (auto-configures rust-analyzer)
vim.g.rustaceanvim = {
  server = {
    settings = {
      ['rust-analyzer'] = {
        checkOnSave = true,
        check = { command = 'clippy' },
        cargo = { allFeatures = true },
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
