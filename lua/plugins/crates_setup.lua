require('crates').setup({ popup = { border = 'rounded' } })

-- In Cargo.toml, override `gh` to show the crate popup instead of LSP hover.
vim.api.nvim_create_autocmd('BufRead', {
  pattern = 'Cargo.toml',
  callback = function(args)
    vim.keymap.set('n', 'gh', require('crates').show_popup,
      { buffer = args.buf, desc = 'Show crate popup' })
  end,
})

-- Per-crate opt-out: a line tagged `# crates: ignore` (or `ignore-upgrade`)
-- documents an intentional version pin, so silence its upgrade noise. The tag
-- works inline (end of the crate line) or on its own comment line above it.
local DIAG_NS = vim.api.nvim_create_namespace('crates.nvim.diagnostic')
local TEXT_NS = vim.api.nvim_create_namespace('crates.nvim')

local function is_comment(line) return line:match('^%s*#') ~= nil end

local function suppress_pinned(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local pinned = {}
  for i, line in ipairs(lines) do
    if line:match('crates:%s*ignore') then
      if is_comment(line) then
        -- Standalone comment: tag the next real crate line below it.
        for j = i + 1, #lines do
          if lines[j]:match('%S') and not is_comment(lines[j]) then
            pinned[j - 1] = true
            break
          end
        end
      else
        pinned[i - 1] = true -- inline tag on the crate line itself
      end
    end
  end
  if next(pinned) == nil then return end

  -- Drop crates.nvim diagnostics on pinned lines, keep the rest. The upgrade
  -- warning lives in the TEXT_NS namespace; section errors live in DIAG_NS.
  for _, ns in ipairs({ TEXT_NS, DIAG_NS }) do
    local kept, changed = {}, false
    for _, d in ipairs(vim.diagnostic.get(buf, { namespace = ns })) do
      if pinned[d.lnum] then changed = true else table.insert(kept, d) end
    end
    if changed then vim.diagnostic.set(ns, buf, kept, { virtual_text = false }) end
  end

  -- Clear the eol virtual-text indicator on pinned lines.
  for lnum in pairs(pinned) do
    vim.api.nvim_buf_clear_namespace(buf, TEXT_NS, lnum, lnum + 1)
  end
end

-- crates.nvim renders asynchronously; schedule past the current tick so both
-- the diagnostic and the virtual text are already drawn before we strip them.
vim.api.nvim_create_autocmd('DiagnosticChanged', {
  pattern = 'Cargo.toml',
  callback = function(args)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(args.buf) then suppress_pinned(args.buf) end
    end)
  end,
})
