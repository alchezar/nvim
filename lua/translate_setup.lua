-- translate.nvim: translate selected text via public Google Translate endpoint.
-- Custom `strip_comments` parser removes line-comment prefixes (-- // # etc.)
-- and block-comment markers (/* */, <!-- -->, --[[ ]], JSDoc *) before sending
-- to Google, so the translation is clean prose.

local function strip_comments_cmd(lines, pos)
  local cs = vim.bo.commentstring
  local prefix, suffix = '', ''
  if cs and cs ~= '' then
    local p, s = cs:match('^(.-)%%s(.-)$')
    if p then
      prefix = vim.trim(p)
      suffix = vim.trim(s or '')
    end
  end

  local start_patterns = { '^%s*/%*+%s?', '^%s*<!%-%-%s?', '^%s*%-%-%[%[%s?', '^%s*%*%s?' }
  local end_patterns   = { '%s*%*+/%s*$', '%s*%-%->%s*$', '%s*%]%]%s*$' }

  for i, line in ipairs(lines) do
    local l = line
    local removed_start, removed_end = 0, 0

    if prefix ~= '' then
      -- Eat prefix, then any repetition of doc-marker chars (e.g. `///`, `//!`, `---`, `##`)
      local _, e = l:find('^%s*' .. vim.pesc(prefix) .. '[/%-#!]*%s?')
      if e then removed_start = removed_start + e; l = l:sub(e + 1) end
    end
    for _, pat in ipairs(start_patterns) do
      local _, e = l:find(pat)
      if e then removed_start = removed_start + e; l = l:sub(e + 1) end
    end

    if suffix ~= '' then
      local s_idx = l:find('%s*' .. vim.pesc(suffix) .. '%s*$')
      if s_idx then removed_end = removed_end + (#l - s_idx + 1); l = l:sub(1, s_idx - 1) end
    end
    for _, pat in ipairs(end_patterns) do
      local s_idx = l:find(pat)
      if s_idx then removed_end = removed_end + (#l - s_idx + 1); l = l:sub(1, s_idx - 1) end
    end

    pos[i].col[1] = pos[i].col[1] + removed_start
    pos[i].col[2] = math.max(pos[i].col[1], pos[i].col[2] - removed_end)
    lines[i] = l
  end

  return lines
end

-- Public helper: run :Translate on the current visual selection but keep the
-- cursor at the END of the selection (default vim behaviour moves it to start,
-- which makes the floating popup cover the original text).
local M = {}
function M.translate_selection(target)
  vim.cmd('normal! \27')  -- <Esc> to leave visual and update '<,'> marks
  local end_line = vim.fn.line("'>")
  vim.cmd(string.format("'<,'>Translate %s -output=floating", target))
  vim.api.nvim_win_set_cursor(0, { end_line, 0 })
end

require('translate').setup({
  default = {
    command = 'google',
    parse_before = 'trim,strip_comments,natural',
  },
  parse_before = {
    strip_comments = { cmd = strip_comments_cmd },
  },
  preset = {
    output = {
      floating = {
        border = 'rounded',
      },
    },
  },
})

return M
