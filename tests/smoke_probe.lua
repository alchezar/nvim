-- Runs in the full-config nvim of tests/test_smoke.lua and writes JSON to
-- $SMOKE_REPORT. `-c` runs before VimEnter, so this waits for it first.
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    -- One tick later, so work the config scheduled on VimEnter has run too.
    vim.schedule(function()
      local config = vim.fn.stdpath('config')
      local failed = {}
      for _, file in ipairs(vim.fn.globpath(config .. '/lua', '**/*.lua', false, true)) do
        local mod = file:sub(#config + 6, -5):gsub('/', '.')
        local ok, err = pcall(require, mod)
        if not ok then failed[#failed + 1] = mod .. ': ' .. tostring(err) end
      end
      vim.fn.writefile({ vim.json.encode({ config = config, failed = failed }) }, vim.env.SMOKE_REPORT)
      -- Skip VimLeavePre, where bookmarks would rewrite the real store.
      os.exit(0)
    end)
  end,
})
