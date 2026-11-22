-- crates.nvim as plugins/crates_setup.lua sets it up: a `crates: ignore` tag
-- silences the upgrade notes of the crate it marks.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'plenary.nvim', 'crates.nvim' } })
      -- crates.nvim asks crates.io through curl; this one fails offline.
      local bin = vim.fn.tempname()
      vim.fn.mkdir(bin, 'p')
      vim.fn.writefile({ '#!/bin/sh', 'exit 7' }, bin .. '/curl')
      vim.fn.setfperm(bin .. '/curl', 'rwxr-xr-x')
      child.lua([[
        vim.env.PATH = ... .. ':' .. vim.env.PATH
        require('plugins.crates_setup')
      ]], { bin })
    end,
    post_once = child.stop,
  },
})

T['an ignore tag silences its crate, inline or on the line above'] = function()
  -- Named, not read: crates.nvim would go fetch versions on BufRead.
  child.api.nvim_buf_set_name(0, vim.fn.tempname() .. '/Cargo.toml')
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    '[dependencies]',
    'serde = "1.0" # crates: ignore',
    '# crates: ignore',
    '',
    'tokio = "1"',
    'anyhow = "1"',
  })
  local got = child.lua([[
    local diag = vim.api.nvim_create_namespace('crates.nvim.diagnostic')
    local text = vim.api.nvim_create_namespace('crates.nvim')
    -- What crates.nvim draws for an outdated crate; its own marks are skipped.
    for _, row in ipairs({ 1, 4, 5 }) do
      vim.api.nvim_buf_set_extmark(0, text, row, 0, { virt_text = { { 'upgrade' } } })
    end
    vim.diagnostic.set(diag, 0, vim.tbl_map(function(row)
      return { lnum = row, col = 0, message = 'upgrade', severity = 2 }
    end, { 1, 4, 5 }))
    vim.wait(200)
    local texts = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, text, 0, -1, { details = true })) do
      if m[4].virt_text and m[4].virt_text[1][1] == 'upgrade' then texts[#texts + 1] = m[2] end
    end
    return {
      diags = vim.tbl_map(function(d) return d.lnum end, vim.diagnostic.get(0, { namespace = diag })),
      texts = texts,
    }
  ]])
  eq(got, { diags = { 5 }, texts = { 5 } })
end

return T
