-- Telescope git preview that keeps the file's own syntax highlighting: the diff
-- body is stored as plain code (markers stripped) and add/delete is shown as a
-- background tint instead of red/green text.

local conf = require('telescope.config').values
local previewers = require('telescope.previewers')
local putils = require('telescope.previewers.utils')
local theme = require('config.theme_colors')

local M = {}

local ns = vim.api.nvim_create_namespace('kinder.git_diff_preview')

-- bg-only tints so treesitter keeps painting the foreground. Re-applied on ColorScheme.
local function apply_hl()
  vim.api.nvim_set_hl(0, 'GitDiffPreviewAdd', { bg = theme.diff.add })
  vim.api.nvim_set_hl(0, 'GitDiffPreviewDelete', { bg = theme.diff.delete })
  vim.api.nvim_set_hl(0, 'GitDiffPreviewHunk', { fg = theme.dark --[[@as string]], italic = true })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })
apply_hl()

local LINE_HL = { ['+'] = 'GitDiffPreviewAdd', ['-'] = 'GitDiffPreviewDelete' }

-- Splits `git diff` output into bare source lines plus per-line marks. Hunk
-- headers become empty lines carrying virtual text, so what treesitter parses
-- stays valid source instead of diff syntax.
local function parse(out)
  local lines, marks, in_hunk = {}, {}, false
  for _, raw in ipairs(out) do
    if raw:sub(1, 2) == '@@' then
      in_hunk = true
      lines[#lines + 1] = ''
      marks[#lines] = { header = raw }
    elseif in_hunk then
      local sign = raw:sub(1, 1)
      if sign == '+' or sign == '-' or sign == ' ' then
        lines[#lines + 1] = raw:sub(2)
        marks[#lines] = LINE_HL[sign] and { hl = LINE_HL[sign] } or nil
      elseif raw == '' then
        lines[#lines + 1] = '' -- context line that was empty
      elseif sign == '\\' then -- "\ No newline at end of file"
        lines[#lines + 1] = ''
        marks[#lines] = { header = raw }
      else
        in_hunk = false -- header of the next file in the same diff
      end
    elseif raw:sub(1, 6) == 'Binary' then
      lines[#lines + 1] = raw
    end
  end
  return lines, marks
end

-- Returns false when the diff carried no hunks, so the caller can fall back.
local function render(bufnr, out, ft, opts)
  local lines, marks = parse(out)
  if #lines == 0 then return false end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for lnum, mark in pairs(marks) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
      line_hl_group = mark.hl,
      virt_text = mark.header and { { mark.header, 'GitDiffPreviewHunk' } } or nil,
      virt_text_pos = mark.header and 'overlay' or nil,
    })
  end
  putils.highlighter(bufnr, ft, opts)
  return true
end

-- Drop-in for previewers.git_file_diff; `entry.path` is absolute, so git runs
-- from the file's own directory and needs no cwd from the picker.
function M.git_status(opts)
  opts = opts or {}
  return previewers.new_buffer_previewer({
    title = 'Git File Diff Preview',
    get_buffer_by_name = function(_, entry) return entry.value end,

    define_preview = function(self, entry)
      if self.state.bufname == entry.value then return end -- cached buffer, already rendered
      local bufnr, winid, path = self.state.bufnr, self.state.winid, entry.path
      if not path or path == '' then return end
      local ft = putils.filetype_detect(path)
      local function preview_file()
        conf.buffer_previewer_maker(path, bufnr, {
          bufname = self.state.bufname,
          winid = winid,
          preview = opts.preview,
          file_encoding = opts.file_encoding,
        })
      end
      if entry.status == '??' then return preview_file() end -- untracked: git has no diff for it

      vim.system(
        { 'git', '--no-pager', 'diff', 'HEAD', '--', path },
        { cwd = vim.fs.dirname(path), text = true },
        vim.schedule_wrap(function(res)
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          local out = vim.split(res.stdout or '', '\n', { plain = true })
          if res.code ~= 0 or not render(bufnr, out, ft, opts) then preview_file() end
        end)
      )
    end,
  })
end

return M
