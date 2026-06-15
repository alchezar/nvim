-- Persistent numbered bookmarks (own module, replaces marks.nvim).
--   m[0-9]    toggle bookmark of group N on the current line
--   `[0-9]    jump to next bookmark of group N in the project (cyclic)
--   dm[0-9]   delete group N in the current buffer
--   <M-m>     on a clean line: add a plain bookmark; otherwise clear the line
--   <leader>m list project bookmarks (Telescope); dd on a row deletes it
--   m{a-zA-Z} / dm{a-zA-Z}  set / delete vim letter marks (signs via marks.nvim)
--   <leader>M list vim letter marks a-z/A-Z (Telescope)
--
-- Bookmarks live as extmarks (so they follow edits in-session) and are saved
-- to a JSON store keyed by absolute path. Each record keeps the line text, so
-- on reopen the bookmark is relocated to that text rather than a stale line nr.

local theme = require('config.theme_colors')

local M = {}
local ns = vim.api.nvim_create_namespace('user_bookmarks')
local store_path = vim.fn.stdpath('data') .. '/bookmarks.json'

-- abspath -> list of { group, line, text }
M.store = {}
-- bufnr -> { [extmark_id] = group }
M.placed = {}

-- All bookmark signs share the theme's yellow accent; the digit tells groups apart.
for g = 0, 9 do
  vim.api.nvim_set_hl(0, 'UserBookmark' .. g, { fg = theme.yellow, bold = true })
end
-- Plain (unnumbered) bookmark: a bookmark glyph instead of a digit.
local PLAIN = 'plain'
local PLAIN_SIGN = vim.fn.nr2char(0xF00C0)
vim.api.nvim_set_hl(0, 'UserBookmarkPlain', { fg = theme.yellow, bold = true })

-- Sign text + highlight for a group: a digit for 0-9, the glyph for a plain mark.
local function sign_for(group)
  if group == PLAIN then return PLAIN_SIGN, 'UserBookmarkPlain' end
  return tostring(group), 'UserBookmark' .. group
end

-- store I/O -------------------------------------------------------------------

local function load_store()
  if vim.fn.filereadable(store_path) == 0 then return end
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(store_path), '\n'))
  end)
  if ok and type(data) == 'table' then M.store = data end
end

local function save_store()
  pcall(vim.fn.writefile, { vim.json.encode(M.store) }, store_path)
  -- Let listeners (the file-tree gutter signs) repaint without polling the store.
  pcall(vim.api.nvim_exec_autocmds, 'User', { pattern = 'BookmarksChanged' })
end

local function abspath(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return nil end
  return vim.fn.fnamemodify(name, ':p')
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function line_text(buf, lnum)
  local l = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  return l and trim(l) or ''
end

-- extmark placement -----------------------------------------------------------

-- Find the line a record should sit on: prefer matching saved text near the
-- stored line, fall back to the raw (clamped) line number.
local function relocate(buf, rec)
  local n = vim.api.nvim_buf_line_count(buf)
  local target = math.max(1, math.min(rec.line, n))
  if rec.text == '' then return target end
  if line_text(buf, target) == rec.text then return target end
  local best, best_dist
  for i = 1, n do
    if line_text(buf, i) == rec.text then
      local d = math.abs(i - rec.line)
      if not best_dist or d < best_dist then best, best_dist = i, d end
    end
  end
  return best or target
end

local function set_mark(buf, group, lnum)
  local text, hl = sign_for(group)
  return vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
    sign_text = text,
    sign_hl_group = hl,
    priority = 200, -- outrank diagnostic/other signs so the bookmark stays visible
  })
end

-- (Re)place all stored bookmarks for a buffer as extmarks.
local function place_buffer(buf)
  local path = abspath(buf)
  if not path or not M.store[path] then return end
  if M.placed[buf] then
    for id in pairs(M.placed[buf]) do vim.api.nvim_buf_del_extmark(buf, ns, id) end
  end
  M.placed[buf] = {}
  for _, rec in ipairs(M.store[path]) do
    local id = set_mark(buf, rec.group, relocate(buf, rec))
    M.placed[buf][id] = rec.group
  end
end

-- Pull live extmark positions back into the store for one buffer.
local function sync_buffer(buf)
  local path = abspath(buf)
  if not path or not M.placed[buf] then return end
  local list = {}
  for id, group in pairs(M.placed[buf]) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {})
    if pos[1] then
      local lnum = pos[1] + 1
      list[#list + 1] = { group = group, line = lnum, text = line_text(buf, lnum) }
    end
  end
  table.sort(list, function(a, b) return a.line < b.line end)
  M.store[path] = #list > 0 and list or nil
end

local function sync_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if M.placed[buf] and vim.api.nvim_buf_is_loaded(buf) then sync_buffer(buf) end
  end
end

-- Project root of the current buffer (same logic as auto-cd) plus a predicate
-- limiting bookmarks to it; with no detectable root, everything is in scope.
local function current_scope()
  local root = require('config.utils').project_root(vim.api.nvim_get_current_buf())
  return root, function(file)
    return not root or file == root or file:sub(1, #root + 1) == root .. '/'
  end
end

-- actions ---------------------------------------------------------------------

local function toggle(group)
  local buf = vim.api.nvim_get_current_buf()
  if not abspath(buf) then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  M.placed[buf] = M.placed[buf] or {}
  -- Same group already on this line -> remove it.
  for _, ext in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { lnum - 1, 0 }, { lnum - 1, -1 }, {})) do
    if M.placed[buf][ext[1]] == group then
      vim.api.nvim_buf_del_extmark(buf, ns, ext[1])
      M.placed[buf][ext[1]] = nil
      sync_buffer(buf); save_store()
      return
    end
  end
  M.placed[buf][set_mark(buf, group, lnum)] = group
  sync_buffer(buf); save_store()
end

local function delete_group(group)
  local buf = vim.api.nvim_get_current_buf()
  if not M.placed[buf] then return end
  for id, g in pairs(M.placed[buf]) do
    if g == group then
      vim.api.nvim_buf_del_extmark(buf, ns, id)
      M.placed[buf][id] = nil
    end
  end
  sync_buffer(buf); save_store()
end

-- Delete one bookmark by its store identity. Unlike delete_group this reaches
-- bookmarks in files that aren't open - e.g. left on another branch - so the
-- picker can drop them without first visiting the file.
local function delete_entry(item)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if M.placed[buf] and abspath(buf) == item.file then
      for id, g in pairs(M.placed[buf]) do
        local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {})
        if g == item.group and pos[1] and pos[1] + 1 == item.line then
          vim.api.nvim_buf_del_extmark(buf, ns, id)
          M.placed[buf][id] = nil
        end
      end
      sync_buffer(buf); save_store()
      return
    end
  end
  -- File not loaded: edit the store record directly.
  local recs = M.store[item.file]
  if not recs then return end
  for i, rec in ipairs(recs) do
    if rec.group == item.group and rec.line == item.line then
      table.remove(recs, i); break
    end
  end
  if #recs == 0 then M.store[item.file] = nil end
  save_store()
end

-- Is a vim letter mark (a-z / A-Z) sitting on this line of the buffer?
local function line_has_letter_mark(buf, lnum)
  for _, m in ipairs(vim.fn.getmarklist(buf)) do
    if m.mark:match("^'%a$") and m.pos[2] == lnum then return true end
  end
  for _, m in ipairs(vim.fn.getmarklist()) do
    if m.mark:match("^'%a$") and m.pos[1] == buf and m.pos[2] == lnum then return true end
  end
  return false
end

-- <M-m>: clear every bookmark/letter mark on the line, or - if it's clean -
-- drop a plain (unnumbered) bookmark.
local function plain_or_delete()
  local buf = vim.api.nvim_get_current_buf()
  if not abspath(buf) then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local mine = M.placed[buf]
      and vim.api.nvim_buf_get_extmarks(buf, ns, { lnum - 1, 0 }, { lnum - 1, -1 }, {})
      or {}
  if #mine > 0 or line_has_letter_mark(buf, lnum) then
    for _, ext in ipairs(mine) do
      vim.api.nvim_buf_del_extmark(buf, ns, ext[1])
      M.placed[buf][ext[1]] = nil
    end
    pcall(function() require('marks').delete_line() end)
  else
    M.placed[buf] = M.placed[buf] or {}
    M.placed[buf][set_mark(buf, PLAIN, lnum)] = PLAIN
  end
  sync_buffer(buf); save_store()
end

-- Cyclic jump over group N across every file in the current project.
local function jump(group)
  sync_all()
  local _, in_scope = current_scope()
  local items = {}
  for path, recs in pairs(M.store) do
    if in_scope(path) then
      for _, rec in ipairs(recs) do
        if rec.group == group then items[#items + 1] = { file = path, line = rec.line } end
      end
    end
  end
  if #items == 0 then return end
  table.sort(items, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)
  local cur_file = abspath(vim.api.nvim_get_current_buf()) or ''
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local target = items[1]
  for _, it in ipairs(items) do
    if it.file > cur_file or (it.file == cur_file and it.line > cur_line) then
      target = it; break
    end
  end
  if target.file ~= cur_file then
    vim.cmd('edit ' .. vim.fn.fnameescape(target.file))
  end
  vim.api.nvim_win_set_cursor(0, { math.min(target.line, vim.api.nvim_buf_line_count(0)), 0 })
end

-- Telescope list --------------------------------------------------------------

local function relpath(file)
  local cwd = vim.fn.getcwd()
  if file:sub(1, #cwd + 1) == cwd .. '/' then return file:sub(#cwd + 2) end
  return vim.fn.fnamemodify(file, ':~')
end

local SEP = '  '

local function list()
  sync_all()
  local root, in_scope = current_scope()
  local entries = {}
  for file, recs in pairs(M.store) do
    if in_scope(file) then
      for _, rec in ipairs(recs) do
        entries[#entries + 1] = { file = file, line = rec.line, group = rec.group, text = rec.text }
      end
    end
  end
  if #entries == 0 then
    vim.notify('No bookmarks', vim.log.levels.INFO)
    return
  end
  local function gkey(g) return type(g) == 'number' and g or 99 end -- plain sorts last
  table.sort(entries, function(a, b)
    local ga, gb = gkey(a.group), gkey(b.group)
    if ga ~= gb then return ga < gb end
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local action_state = require('telescope.actions.state')

  pickers.new({}, {
    prompt_title = root and 'Bookmarks (project)' or 'Bookmarks (all)',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(item)
        local gtext, ghl = sign_for(item.group)
        local path = relpath(item.file)
        local lc = tostring(item.line)
        local line = gtext .. SEP .. path .. SEP .. lc .. SEP .. item.text
        local p0 = #gtext
        local p1 = p0 + #SEP + #path
        local p2 = p1 + #SEP + #lc
        local p3 = p2 + #SEP + #item.text
        return {
          value = item,
          ordinal = path .. ' ' .. item.text,
          filename = item.file,
          lnum = item.line,
          display = function()
            return line, {
              { { 0, p0 },         ghl },
              { { p0 + #SEP, p1 }, 'TelescopeResultsFileName' },
              { { p1 + #SEP, p2 }, 'TelescopeResultsLineNr' },
              { { p2 + #SEP, p3 }, 'TelescopeResultsNormal' },
            }
          end,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    -- `dd` removes the bookmark under the cursor without closing the picker.
    attach_mappings = function(prompt_bufnr, map)
      map('n', 'dd', function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        picker:delete_selection(function(selection)
          delete_entry(selection.value)
          return true
        end)
      end)
      return true
    end,
  }):find()
end

-- marks.nvim is kept ONLY for vim letter marks a-z/A-Z: gutter signs, set with
-- `m{mark}`, delete with `dm{mark}`. All numbered-group mappings are off so they
-- never clash with our own m0-9 / dm0-9 above.
require('marks').setup({
  default_mappings = false,
  signs = true,
  mappings = { set = 'm', delete = 'dm' },
})

-- keymaps & autocmds ----------------------------------------------------------

for i = 0, 9 do
  vim.keymap.set('n', 'm' .. i, function() toggle(i) end, { desc = 'Toggle bookmark ' .. i })
  vim.keymap.set('n', '`' .. i, function() jump(i) end, { desc = 'Jump to bookmark ' .. i })
  vim.keymap.set('n', 'dm' .. i, function() delete_group(i) end, { desc = 'Delete bookmark group ' .. i })
end
vim.keymap.set('n', '<M-m>', plain_or_delete, { desc = 'Toggle plain bookmark / clear marks on line' })
vim.keymap.set('n', '<leader>m', list, { desc = 'List all bookmarks (Telescope)', silent = true })
vim.keymap.set('n', '<leader>M', function() require('telescope.builtin').marks() end,
  { desc = 'List letter marks (Telescope)', silent = true })

local group = vim.api.nvim_create_augroup('UserBookmarks', { clear = true })
vim.api.nvim_create_autocmd('BufReadPost', {
  group = group,
  callback = function(args) place_buffer(args.buf) end,
})
vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufLeave' }, {
  group = group,
  callback = function(args) sync_buffer(args.buf) end,
})
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    sync_all(); save_store()
  end,
})

load_store()
-- Place marks in buffers already open when this module loads.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then place_buffer(buf) end
end

return M
