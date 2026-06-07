-- vim-startify dashboard. Project paths come from lua/config/projects.lua (gitignored).

local function load_projects()
  local ok, projects = pcall(require, 'config.projects')
  return ok and projects or {}
end

-- _order first, remaining groups alphabetically.
local function group_order(projects)
  local ordered, seen = {}, {}
  if type(projects._order) == 'table' then
    for _, name in ipairs(projects._order) do
      if type(projects[name]) == 'table' then
        table.insert(ordered, name)
        seen[name] = true
      end
    end
  end
  local rest = {}
  for k, v in pairs(projects) do
    if k ~= '_order' and not seen[k] and type(v) == 'table' then
      table.insert(rest, k)
    end
  end
  table.sort(rest)
  for _, n in ipairs(rest) do table.insert(ordered, n) end
  return ordered
end

local function total_projects(projects)
  local n = 0
  for k, v in pairs(projects) do
    if k ~= '_order' and type(v) == 'table' then n = n + #v end
  end
  return n
end

-- `tcd <path> | Startify` refreshes Recent/Sessions against the new cwd.
function _G.startify_projects_group(group_name)
  local group   = load_projects()[group_name] or {}
  local entries = {}
  for _, item in ipairs(group) do
    local path, name
    if type(item) == 'string' then
      path = item
      name = vim.fn.fnamemodify(path, ':t')
    else
      path = item.path
      name = item.name or vim.fn.fnamemodify(path, ':t')
    end
    table.insert(entries, {
      line = name,
      cmd  = 'tcd ' .. vim.fn.fnameescape(path) .. ' | Startify',
    })
  end
  return entries
end

vim.g.startify_enable_special = 0
vim.g.startify_fortune_use_unicode = 1

-- Dim the directory portion of Recent files so the filename stays visually primary.
local function apply_startify_hl()
  local theme = require('config.theme_colors')
  vim.api.nvim_set_hl(0, 'StartifyPath', { fg = theme.dark })
  vim.api.nvim_set_hl(0, 'StartifySlash', { fg = theme.dark })
  vim.api.nvim_set_hl(0, 'StartifyTipKey', { fg = theme.red, bold = true })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_startify_hl })
apply_startify_hl()

local function load_extra_quotes()
  local ok, quotes = pcall(require, 'config.quotes')
  return ok and quotes or {}
end

local function load_vim_tips()
  local ok, tips = pcall(require, 'config.vim_tips')
  return ok and tips.get() or {}
end

math.randomseed((vim.uv or vim.loop).hrtime() % 2147483647)

-- The element currently drawn in the cow balloon, kept so `y` can copy it.
local shown
-- Tree's left offset, refreshed by apply_layout so centering survives the tree.
local last_win_col = 0

local function block_width(lines)
  local w = 0
  for _, l in ipairs(lines) do w = math.max(w, vim.fn.strdisplaywidth(l)) end
  return w
end

-- Strip the common left indent so a block can be centered by its true shape.
local function dedent(lines)
  local m = math.huge
  for _, l in ipairs(lines) do
    if l:match('%S') then m = math.min(m, #l:match('^%s*')) end
  end
  if m == math.huge or m == 0 then return lines end
  return vim.tbl_map(function(l) return l:sub(m + 1) end, lines)
end

-- Left-pad a block to sit centered on screen by its own width, minus win_col.
local function center(lines, total)
  local left = math.max(0, math.floor((total - block_width(lines)) / 2) - last_win_col)
  local p = string.rep(' ', left)
  return vim.tbl_map(function(l) return p .. l end, lines)
end

-- Pick one pool entry, remember it, and render the cow around it. Driving the
-- choice ourselves (instead of letting cowsay() pick) is what lets `y` know
-- exactly which tip/quote is on screen. The balloon and the cow are centered
-- independently so each lands on screen center regardless of text width.
function _G.startify_cow_render()
  local pool = vim.g.startify_custom_header_quotes or {}
  if #pool == 0 then return {} end
  shown       = pool[math.random(#pool)]
  local total = vim.o.columns
  local boxed = vim.fn['startify#fortune#boxed'](shown)
  local full  = vim.fn['startify#fortune#cowsay'](shown)
  local cow   = {}
  for i = #boxed + 1, #full do cow[#cow + 1] = full[i] end
  local out = center(boxed, total)
  vim.list_extend(out, center(dedent(cow), total))
  return out
end

local function trim(s) return (s or ''):gsub('^%s+', ''):gsub('%s+$', '') end

-- Two non-empty lines with no author credit is one of our tips (`key`/`desc`),
-- as opposed to a quote.
local function is_tip(item)
  if type(item) ~= 'table' or #item ~= 2 then return false end
  return trim(item[1]) ~= '' and trim(item[2]) ~= '' and not trim(item[2]):match('^%-')
end

-- Flatten a pool entry to one line: a tip becomes `key -> desc`, a quote joins.
local function shown_to_text(item)
  if type(item) ~= 'table' then return tostring(item) end
  if is_tip(item) then return trim(item[1]) .. '  ->  ' .. trim(item[2]) end
  local parts = {}
  for _, l in ipairs(item) do
    local s = trim(l)
    if s ~= '' then parts[#parts + 1] = s end
  end
  return table.concat(parts, ' ')
end

local tip_ns = vim.api.nvim_create_namespace('startify_tip_key')

-- Color the command red on the balloon's first content row. The command sits
-- right after the `│ ` border; the description row starts with spaces, so a
-- prefix match uniquely targets the key line.
local function highlight_tip_key(buf)
  vim.api.nvim_buf_clear_namespace(buf, tip_ns, 0, -1)
  if not is_tip(shown) then return end
  local cmd = trim(shown[1])
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 14, false)) do
    local prefix = line:match('^(.-│ )')
    if prefix and line:sub(#prefix + 1, #prefix + #cmd) == cmd then
      vim.api.nvim_buf_set_extmark(buf, tip_ns, i - 1, #prefix,
        { end_col = #prefix + #cmd, hl_group = 'StartifyTipKey' })
      return
    end
  end
end

-- In the startify buffer, `y` copies the shown tip to the clipboard instead of
-- yanking the project/file line under the cursor.
vim.api.nvim_create_autocmd('FileType', {
  pattern  = 'startify',
  callback = function(ev)
    vim.keymap.set('n', 'y', function()
      if not shown then return end
      local text = shown_to_text(shown)
      vim.fn.setreg('+', text)
      vim.fn.setreg('"', text)
      vim.notify('Copied: ' .. text)
    end, { buffer = ev.buf, nowait = true, desc = 'Copy startify tip' })
  end,
})

local content_width = 85
local last_pad_n    = nil

local function vim_escape(s) return (s:gsub("'", "''")) end

-- One Vim funcref per group -> Startify renders each as its own top-level section.
local function register_group_funcrefs(groups)
  for i, name in ipairs(groups) do
    vim.cmd(string.format([[
      function! g:StartifyProjects_%d() abort
        return luaeval('_G.startify_projects_group(_A)', '%s')
      endfunction
    ]], i, vim_escape(name)))
  end
end

-- Center against full editor width, then subtract win_col so the layout lands
-- at the same screen position with or without the file tree.
local function apply_layout(win_col)
  last_win_col   = win_col or 0
  local projects = load_projects()
  local groups   = group_order(projects)
  register_group_funcrefs(groups)

  local total_w                = vim.o.columns
  local pad_n                  = math.max(4, math.floor((total_w - content_width) / 2) - (win_col or 0))
  local pad                    = string.rep(' ', pad_n)

  vim.g.startify_pad_str       = pad
  vim.g.startify_padding_left  = pad_n
  vim.g.startify_custom_header = "luaeval('_G.startify_cow_render()')"
  vim.g.startify_files_number  = 100 - total_projects(projects)

  local items                  = {}
  for i, name in ipairs(groups) do
    table.insert(items, string.format(
      "{ 'type': function('g:StartifyProjects_%d'), 'header': ['%s   %s'] }",
      i, pad, vim_escape(name)))
  end
  table.insert(items, string.format("{ 'type': 'files',    'header': ['%s   Recent files'] }", pad))
  table.insert(items, string.format("{ 'type': 'sessions', 'header': ['%s   Sessions']     }", pad))
  table.insert(items, string.format("{ 'type': 'commands', 'header': ['%s   Commands']     }", pad))
  vim.cmd('let g:startify_lists = [' .. table.concat(items, ', ') .. ']')

  return pad_n
end

vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = function()
    local quotes = vim.fn['startify#fortune#predefined_quotes']()
    vim.list_extend(quotes, load_extra_quotes())
    vim.list_extend(quotes, load_vim_tips())
    vim.g.startify_custom_header_quotes = quotes
    apply_layout(0)
  end,
})

-- Find first `[idx]` entry below the Recent files header.
local function cursor_to_recent_files()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= 'startify' then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:find('Recent files', 1, true) then
      for j = i + 1, math.min(i + 30, #lines) do
        local col = lines[j]:find('%[')
        if col then
          vim.api.nvim_win_set_cursor(0, { j, col }) -- land on the digit, not the `[`
          return
        end
      end
    end
  end
end

-- Re-indent `[idx]` entries to pad_n: the plugin's frozen s:leftpad ignores our
-- dynamic centering. Navigation is line-keyed, so shifting whitespace is safe.
local function align_entries(buf, pad_n)
  local pad     = string.rep(' ', pad_n)
  local lines   = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = false
  for i, line in ipairs(lines) do
    local rest = line:match('^%s*(%[.*)$')
    if rest then
      lines[i] = pad .. rest; changed = true
    end
  end
  if not changed then return end
  local mod = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = mod
  vim.bo[buf].modified = false -- else the next Startify's enew aborts with E37
end

-- Replace the plugin's CursorMoved (it pins to a frozen s:fixed_column that our
-- centering invalidates): keep the cursor on the `[idx]`, skipping headers/blanks.
local function setup_cursor(buf)
  vim.api.nvim_clear_autocmds({ event = 'CursorMoved', buffer = buf })
  local prev_row
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer   = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local function col_at(r) return lines[r] and lines[r]:find('%[') end
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local dir = (prev_row and row < prev_row) and -1 or 1
      local r   = row
      while r >= 1 and r <= #lines and not col_at(r) do r = r + dir end
      if r < 1 or r > #lines then -- past an edge: walk back to the nearest entry
        r = row
        repeat r = r - dir until r < 1 or r > #lines or col_at(r)
      end
      local col = col_at(r)
      if not col then return end
      prev_row = r
      -- 1-based `[` position as a 0-based column lands on the digit after it.
      vim.api.nvim_win_set_cursor(0, { r, col })
    end,
  })
end

-- vim.o.columns at VimEnter can be stale (Neovide settles after); recompute on every
-- Startify render and re-issue once if pad changed. Same handler covers WinResized.
vim.api.nvim_create_autocmd('User', {
  pattern  = 'StartifyReady',
  callback = function()
    vim.wo.wrap   = false
    local win     = vim.api.nvim_get_current_win()
    local win_col = vim.api.nvim_win_get_position(win)[2]
    local needed  = math.max(4, math.floor((vim.o.columns - content_width) / 2) - win_col)
    if needed ~= last_pad_n then
      last_pad_n = needed
      apply_layout(win_col)
      vim.schedule(function() vim.cmd('Startify') end)
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    align_entries(buf, last_pad_n)
    setup_cursor(buf)
    cursor_to_recent_files()
    highlight_tip_key(buf)
  end,
})

vim.api.nvim_create_autocmd('WinResized', {
  callback = function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'startify' then
        local win_col = vim.api.nvim_win_get_position(win)[2]
        last_pad_n    = apply_layout(win_col)
        vim.api.nvim_win_call(win, function() vim.cmd('Startify') end)
        break
      end
    end
  end,
})
