-- Install parsers manually after first launch:
--   :TSInstall rust toml lua typescript tsx javascript json python

-- Preload parsers used purely as INJECTION targets (i.e. no buffer ever has
-- their filetype, so the FileType autocmd below never fires for them).
-- Without this, opening a non-rust file first (e.g. lua) means the rust tree
-- is built before the sql parser is registered -> sqlx::query! injection
-- silently produces no SQL tree and falls back to plain @string.rust on the
-- initial highlight pass.
for _, lang in ipairs({ 'sql' }) do
  pcall(vim.treesitter.language.add, lang)
end

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
