-- After first launch: `:TSInstall rust toml lua typescript tsx javascript json python`.

-- Preload injection-only parsers (no buffer has their ft, so FileType never fires).
-- Without this, opening a non-rust file first means sqlx::query! injections
-- silently fall back to @string.rust on the initial highlight pass.
for _, lang in ipairs({ 'sql' }) do
  pcall(vim.treesitter.language.add, lang)
end

vim.api.nvim_create_autocmd('FileType', {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- SQL parser misses `FOR UPDATE`/`FOR SHARE` inside sqlx::query!(); force-highlight via matchadd.
vim.api.nvim_create_autocmd('BufWinEnter', {
  pattern = '*.rs',
  callback = function()
    if vim.w.sqlx_for_match then return end
    vim.w.sqlx_for_match = vim.fn.matchadd('@keyword.sql',
      [[\v(\/\/.*)@<!<FOR\s+(NO\s+KEY\s+UPDATE|KEY\s+SHARE|UPDATE|SHARE)>]])
  end,
})
