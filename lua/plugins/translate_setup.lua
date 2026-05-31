-- translate.nvim via Google. Custom strip_comments parser removes line/block
-- comment markers (-- // # /* */ <!-- --> --[[ ]] JSDoc *) before sending.

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
      -- Eat prefix and any doc-marker repetition (///, //!, ---, ##).
      local _, e = l:find('^%s*' .. vim.pesc(prefix) .. '[/%-#!]*%s?')
      if e then
        removed_start = removed_start + e; l = l:sub(e + 1)
      end
    end
    for _, pat in ipairs(start_patterns) do
      local _, e = l:find(pat)
      if e then
        removed_start = removed_start + e; l = l:sub(e + 1)
      end
    end

    if suffix ~= '' then
      local s_idx = l:find('%s*' .. vim.pesc(suffix) .. '%s*$')
      if s_idx then
        removed_end = removed_end + (#l - s_idx + 1); l = l:sub(1, s_idx - 1)
      end
    end
    for _, pat in ipairs(end_patterns) do
      local s_idx = l:find(pat)
      if s_idx then
        removed_end = removed_end + (#l - s_idx + 1); l = l:sub(1, s_idx - 1)
      end
    end

    pos[i].col[1] = pos[i].col[1] + removed_start
    pos[i].col[2] = math.max(pos[i].col[1], pos[i].col[2] - removed_end)
    lines[i] = l
  end

  return lines
end

-- :Translate the visual selection; park cursor BELOW the selection so the
-- floating output (relative=cursor, row=1) doesn't cover the source text.
-- Falls back to the last selected line when selection ends at EOF.
local M = {}
function M.translate_selection(target)
  vim.cmd('normal! \27') -- <Esc> to update '<,'> marks
  local end_line  = vim.fn.line("'>")
  local last_line = vim.fn.line('$')
  vim.cmd(string.format("'<,'>Translate %s -output=floating", target))
  local target_line = math.min(end_line + 1, last_line)
  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
end

-- Custom floating output: clamp width to a fraction of editor columns and
-- enable soft word-wrap so long single-line translations don't overflow.
local floating_max_ratio = 0.8
local _float

local function close_float()
  if _float then
    pcall(vim.api.nvim_win_close, _float.win, true)
    pcall(vim.api.nvim_buf_delete, _float.buf, { force = true })
    _float = nil
  end
end

local function floating_cmd(lines)
  if type(lines) == 'string' then lines = { lines } end
  close_float()

  local options = require('translate.config').get('preset').output.floating
  local max_w = math.max(1, math.floor(vim.o.columns * floating_max_ratio))

  local widest = 0
  for _, l in ipairs(lines) do
    widest = math.max(widest, vim.api.nvim_strwidth(l))
  end
  local width = math.max(1, math.min(widest, max_w))

  -- Account for soft-wrap when computing height.
  local height = 0
  for _, l in ipairs(lines) do
    local w = math.max(1, vim.api.nvim_strwidth(l))
    height = height + math.ceil(w / width)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  vim.api.nvim_set_option_value('filetype', options.filetype, { buf = buf })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = options.relative,
    style = options.style,
    width = width,
    height = height,
    row = options.row,
    col = options.col,
    border = options.border,
    zindex = options.zindex,
  })
  vim.api.nvim_set_option_value('wrap', true, { win = win })
  vim.api.nvim_set_option_value('linebreak', true, { win = win })

  _float = { win = win, buf = buf }
  vim.api.nvim_create_autocmd('CursorMoved', { callback = close_float, once = true })
end

require('translate').setup({
  default = {
    command = 'google',
    parse_before = 'trim,strip_comments,natural',
  },
  parse_before = {
    strip_comments = { cmd = strip_comments_cmd },
  },
  output = {
    floating = { cmd = floating_cmd },
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
