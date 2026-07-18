-- Off by default; ModeChanged in config.options toggles it for visual/insert.
local char, virtcolumn, hl = '▏', '81,101', 'VirtColumn'
require('virt-column').setup({ enabled = false, char = char, virtcolumn = virtcolumn, highlight = hl })

-- Extend the rule across LSP codelens virtual lines ("N references"), which the
-- decoration provider can't reach, so there are no gaps above rust-analyzer items.
if not vim.g.virtcolumn_codelens_patched then
  vim.g.virtcolumn_codelens_patched = true
  local cols = vim.tbl_map(tonumber, vim.split(virtcolumn, ','))
  table.sort(cols)
  local enabled = false      -- mirror virt-column: only draw in visual/insert

  local function strip(line) -- drop the pad+char chunks we appended (kept trailing)
    for i, ch in ipairs(line) do
      if ch[1] == char and ch[2] == hl then
        for j = #line, i - 1, -1 do table.remove(line, j) end
        return
      end
    end
  end

  local function decorate(line)
    local w = 0
    for _, ch in ipairs(line) do w = w + vim.fn.strdisplaywidth(ch[1]) end
    for _, c in ipairs(cols) do -- pad to just before the column, then the rule char
      if w < c then
        line[#line + 1] = { (' '):rep(c - 1 - w), 'LspCodeLensSeparator' }
        line[#line + 1] = { char, hl }
        w = c
      end
    end
  end

  local is_codelens = {}
  local function codelens_ns(ns) -- classify each namespace once by name
    if is_codelens[ns] == nil then
      is_codelens[ns] = false
      for name, id in pairs(vim.api.nvim_get_namespaces()) do
        if id == ns and name:find('nvim.lsp.codelens', 1, true) then is_codelens[ns] = true end
      end
    end
    return is_codelens[ns]
  end

  local orig = vim.api.nvim_buf_set_extmark
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
    if enabled and opts and opts.virt_lines and codelens_ns(ns) then
      for _, line in ipairs(opts.virt_lines) do decorate(line) end
    end
    return orig(buf, ns, row, col, opts)
  end

  -- Codelens caches rendered rows, so on mode switch redraw its existing marks.
  vim.api.nvim_create_autocmd('ModeChanged', {
    callback = function()
      local mode = vim.v.event.new_mode
      enabled = mode:match('^[vV\22]') ~= nil or mode:match('^[iR]') ~= nil
      local buf = vim.api.nvim_get_current_buf()
      for name, ns in pairs(vim.api.nvim_get_namespaces()) do
        if name:find('nvim.lsp.codelens', 1, true) then
          for _, e in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
            local det = e[4]
            if det and det.virt_lines then
              for _, line in ipairs(det.virt_lines) do
                strip(line)
                if enabled then decorate(line) end
              end
              orig(buf, ns, e[2], e[3], {
                id = e[1],
                virt_lines = det.virt_lines,
                virt_lines_above = det.virt_lines_above,
                virt_lines_overflow = det.virt_lines_overflow,
                hl_mode = 'combine',
              })
            end
          end
        end
      end
    end,
  })
end
