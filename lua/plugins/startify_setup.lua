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
  local projects = load_projects()
  local groups   = group_order(projects)
  register_group_funcrefs(groups)

  local total_w                = vim.o.columns
  local pad_n                  = math.max(4, math.floor((total_w - content_width) / 2) - (win_col or 0))
  local pad                    = string.rep(' ', pad_n)

  vim.g.startify_pad_str       = pad
  vim.g.startify_padding_left  = pad_n
  vim.g.startify_custom_header =
  "map(startify#fortune#cowsay(), 'g:startify_pad_str . v:val')"
  vim.g.startify_files_number  = 100 - total_projects(projects)

  -- Setting g:startify_padding_left alone leaves items at stale pad; only set_padding refreshes s:leftpad.
  pcall(vim.fn['startify#set_padding'], pad_n)

  local items = {}
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
          vim.api.nvim_win_set_cursor(0, { j, col - 1 })
          return
        end
      end
    end
  end
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
    cursor_to_recent_files()
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
