-- Install parsers manually after first launch:
--   :TSInstall rust toml lua typescript tsx javascript json
vim.api.nvim_create_autocmd('FileType', {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- SQL parser misses `FOR UPDATE` / `FOR SHARE` row-locking clauses inside
-- sqlx::query!() raw strings, so they fall back to @string.rust (yellow).
-- Force-highlight them as keywords via window-local matchadd.
vim.api.nvim_create_autocmd('BufWinEnter', {
  pattern = '*.rs',
  callback = function()
    if vim.w.sqlx_for_match then return end
    vim.w.sqlx_for_match = vim.fn.matchadd('@keyword.sql',
      [[\v(\/\/.*)@<!<FOR\s+(NO\s+KEY\s+UPDATE|KEY\s+SHARE|UPDATE|SHARE)>]])
  end,
})
