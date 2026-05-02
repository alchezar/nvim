-- Install parsers manually after first launch:
--   :TSInstall rust toml lua typescript tsx javascript json
vim.api.nvim_create_autocmd('FileType', {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})
