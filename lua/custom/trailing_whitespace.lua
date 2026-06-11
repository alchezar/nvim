-- Flags trailing whitespace as HINT diagnostics, reusing the LSP diagnostic
-- pipeline: the gutter sign and the nvim-tree dot are drawn by vim.diagnostic
-- itself, so no custom glyph or colour lives here. This namespace shows signs
-- only - virtual_text/underline are off so the dirty lines stay quiet.

local ns = vim.api.nvim_create_namespace('user_trailing_whitespace')
vim.diagnostic.config({ virtual_text = false, underline = false, signs = true }, ns)

-- Real, editable file buffers only; buftype filters out nvim-tree, dbui, terminals.
local function eligible(buf)
  return vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buftype == ''
      and vim.bo[buf].modifiable
end

local function scan(buf)
  if not eligible(buf) then return end
  local diags = {}
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local s = line:find('%s+$')
    if s then
      diags[#diags + 1] = {
        lnum = i - 1,
        col = s - 1,
        end_lnum = i - 1,
        end_col = #line,
        severity = vim.diagnostic.severity.HINT,
        source = 'trailing',
        message = 'Trailing whitespace',
      }
    end
  end
  vim.diagnostic.set(ns, buf, diags)
end

-- Refresh in normal mode only (InsertLeave, not TextChangedI) so marks don't
-- flicker while a line is still being typed.
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'TextChanged', 'InsertLeave' }, {
  group = vim.api.nvim_create_augroup('user_trailing_whitespace', { clear = true }),
  callback = function(args) scan(args.buf) end,
})

-- Buffers already open when this module loads (e.g. the file nvim started on).
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then scan(buf) end
end
