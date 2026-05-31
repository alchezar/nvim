require('crates').setup({ popup = { border = 'rounded' } })

-- In Cargo.toml, override `gh` to show the crate popup instead of LSP hover.
vim.api.nvim_create_autocmd('BufRead', {
  pattern = 'Cargo.toml',
  callback = function(args)
    vim.keymap.set('n', 'gh', require('crates').show_popup,
      { buffer = args.buf, desc = 'Show crate popup' })
  end,
})
