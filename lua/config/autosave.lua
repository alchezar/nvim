-- Auto-save without formatting.
-- Manual `:w` keeps full conform.nvim format-on-save behavior.
-- This uses `noautocmd write` to bypass BufWritePre (where conform hooks).

local group = vim.api.nvim_create_augroup('autosave', { clear = true })

vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged', 'FocusLost', 'BufLeave' }, {
  group = group,
  callback = function(args)
    local buf = args.buf
    if vim.bo[buf].buftype ~= '' then return end
    if not vim.bo[buf].modifiable or vim.bo[buf].readonly then return end
    if not vim.bo[buf].modified then return end
    if vim.api.nvim_buf_get_name(buf) == '' then return end

    vim.api.nvim_buf_call(buf, function()
      vim.cmd('silent! noautocmd write')
    end)
  end,
})
