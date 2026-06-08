-- nvim-tree: file explorer sidebar. Keymaps in lua/keys.lua.

-- Shared glyph for both diagnostic and bookmark gutter signs; change here to try others.
-- ◆ ■ ▰ ▸ ◉ ⬤ ● •
local gutter_dot = '*'

-- Natural sort: `9` before `10`, not lexicographic `10, 4, 9`.
local function natural_lt(a, b)
  local ai, bi = 1, 1
  while ai <= #a and bi <= #b do
    local ac = a:sub(ai, ai)
    local bc = b:sub(bi, bi)
    if ac:match('%d') and bc:match('%d') then
      local a_num = a:match('%d+', ai)
      local b_num = b:match('%d+', bi)
      local an, bn = tonumber(a_num), tonumber(b_num)
      if an ~= bn then return an < bn end
      ai = ai + #a_num
      bi = bi + #b_num
    else
      if ac ~= bc then return ac < bc end
      ai = ai + 1
      bi = bi + 1
    end
  end
  return #a < #b
end

-- Custom sorter bypasses nvim-tree's `folders_first`, so handle it here.
local function tree_sorter(nodes)
  table.sort(nodes, function(a, b)
    if a.type ~= b.type then
      if a.type == 'directory' then return true end
      if b.type == 'directory' then return false end
    end
    -- Landmarks pinned to top: README.md, then mod.rs.
    local a_readme = a.name:lower() == 'readme.md'
    local b_readme = b.name:lower() == 'readme.md'
    if a_readme and not b_readme then return true end
    if b_readme and not a_readme then return false end
    if a.name == 'mod.rs' and b.name ~= 'mod.rs' then return true end
    if b.name == 'mod.rs' and a.name ~= 'mod.rs' then return false end
    return natural_lt(a.name:lower(), b.name:lower())
  end)
end

require('nvim-tree').setup({
  -- Tree follows the global cwd (set to the project root by auto_cd_to_project_root).
  -- Re-roots on a real project change; within a project getcwd == root so focus never reloads.
  sync_root_with_cwd = true,
  respect_buf_cwd = false,
  sort = { sorter = tree_sorter },
  view = { width = 40, cursorline = false },
  -- Reveal the open file without re-running git per BufEnter (update_root would; the lag).
  update_focused_file = {
    enable = true,
    update_root = {
      enable = false,
      ignore_list = {},
    },
  },
  root_dirs = {},
  git = { enable = true },
  filesystem_watchers = { enable = true },

  filters = {
    -- Show git-ignored files (.env, .secret/...): nvim-tree runs `git status --ignored=matching`,
    -- which does NOT recurse into ignored dirs, so this is cheap. Hide only the huge target/.
    git_ignored = false,
    custom = { '^target$', '^\\.DS_Store$' },
  },
  diagnostics = {
    enable = true,
    show_on_dirs = true,
    icons = {
      hint = gutter_dot,
      info = gutter_dot,
      warning = gutter_dot,
      error = gutter_dot,
    },
  },
  renderer = {
    highlight_git = 'name',
    highlight_diagnostics = 'name',
    icons = {
      -- nvim-tree docs type padding as string; bundled stub says table -> false positive.
      ---@diagnostic disable-next-line: assign-type-mismatch
      padding = '  ',
      show = { git = false },
      glyphs = {
        folder = {
          default    = '\u{F024B}',
          open       = '\u{F0770}',
          empty      = '\u{F0256}',
          empty_open = '\u{F0DCF}',
        },
      },
    },
  },
})

local function apply_tree_hl()
  local theme = require('config.theme_colors')
  vim.api.nvim_set_hl(0, 'NvimTreeNormal', { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileIgnoredHL', { fg = theme.brown })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderIgnoredHL', { fg = theme.brown })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileDirtyHL', { fg = theme.blue })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderDirtyHL', { fg = theme.blue })
  vim.api.nvim_set_hl(0, 'NvimTreeFolderName', { fg = theme.silver, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTreeOpenedFolderName', { fg = theme.silver, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTreeEmptyFolderName', { fg = theme.silver, bold = true, italic = true })
  vim.api.nvim_set_hl(0, 'NvimTreeFolderIcon', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'NvimTreeOpenedFolderIcon', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'NvimTreeRootFolder', { fg = theme.silver, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTreeSymlinkFolderName', { fg = theme.silver, bold = true, italic = true })
  vim.api.nvim_set_hl(0, 'NvimTreeCursorLine', { bg = theme.black })
  vim.api.nvim_set_hl(0, 'NvimTreeCopiedHL', { link = 'NvimTreeNormal' }) -- Render copied files like any other
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_tree_hl })
apply_tree_hl()

-- Annotate mod.rs / README.md (case-insensitive) with `[parent]` virtual text.
local mod_ns = vim.api.nvim_create_namespace('nvim_tree_mod_rs_parent')
vim.api.nvim_set_hl(0, 'NvimTreeModRsParent', { fg = require('config.theme_colors').silver, bold = true })

require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  local bufnr = payload and payload.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, mod_ns, 0, -1)

  local core = require('nvim-tree.core')
  local explorer = core.get_explorer()
  if not explorer then return end

  local start_line = core.get_nodes_starting_line()
  local nodes_by_line = explorer:get_nodes_by_line(start_line)
  for line, node in pairs(nodes_by_line) do
    local is_special = node and node.name
        and (node.name == 'mod.rs' or node.name:lower() == 'readme.md')
    if is_special and node.parent and node.parent.name and node.parent.nodes then
      -- Skip when there are no sibling subdirs: parent is obvious from the row above.
      local has_subdir = false
      for _, sibling in ipairs(node.parent.nodes) do
        if sibling.type == 'directory' then
          has_subdir = true
          break
        end
      end
      if has_subdir then
        vim.api.nvim_buf_set_extmark(bufnr, mod_ns, line - 1, 0, {
          virt_text = { { '[' .. node.parent.name .. ']', 'NvimTreeModRsParent' } },
          virt_text_pos = 'eol',
        })
      end
    end
  end
end)

-- FileType catches first-open (BufWinEnter fires before filetype is set).
local function enable_tree_cursorline(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.wo[win].cursorline = true
    end
  end
end
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'NvimTree',
  callback = function(args)
    vim.schedule(function() enable_tree_cursorline(args.buf) end)
  end,
})
vim.api.nvim_create_autocmd('BufWinEnter', {
  pattern = 'NvimTree_*',
  callback = function(args)
    if vim.bo[args.buf].filetype == 'NvimTree' then
      enable_tree_cursorline(args.buf)
    end
  end,
})

-- Strip cursorline inherited from NvimTree on :split. Skip while blame is active.
vim.api.nvim_create_autocmd('BufWinEnter', {
  callback = function(args)
    if vim.bo[args.buf].buftype ~= '' then return end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'blame' then return end
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == args.buf then
        vim.wo[win].cursorline = false
      end
    end
  end,
})

-- Overlay microchip icon for extensionless files with +x bit (Rust/Go/etc binaries).
local exec_ns = vim.api.nvim_create_namespace('nvim_tree_exec_icon')
vim.api.nvim_set_hl(0, 'NvimTreeExecutableIcon', { fg = require('config.theme_colors').green })

local function is_extensionless_executable(node)
  if not node or node.type ~= 'file' then return false end
  if not node.name or node.name:find('%.') then return false end
  if not node.absolute_path then return false end
  local stat = vim.uv.fs_stat(node.absolute_path)
  if not stat then return false end
  return bit.band(stat.mode, 73) ~= 0 -- 0o111: any +x bit (owner/group/other)
end

require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  local bufnr = payload and payload.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, exec_ns, 0, -1)

  local core = require('nvim-tree.core')
  local explorer = core.get_explorer()
  if not explorer then return end

  local start_line = core.get_nodes_starting_line()
  local nodes_by_line = explorer:get_nodes_by_line(start_line)
  for line, node in pairs(nodes_by_line) do
    if is_extensionless_executable(node) then
      local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''
      local name_byte = text:find(node.name, 1, true)
      if name_byte then
        -- Split prefix into leading padding (spaces) and icon+space; place virt_text
        -- at the padding width and pad it to match the original icon+space display width
        -- so it cleanly overlays whatever the default icon was.
        local pre_name = text:sub(1, name_byte - 1)
        local icon_part = pre_name:gsub('^%s+', '')
        local padding_w = vim.fn.strdisplaywidth(pre_name) - vim.fn.strdisplaywidth(icon_part)
        local target_w = vim.fn.strdisplaywidth(icon_part)
        local virt = '\u{f2db}' -- 
        local virt_w = vim.fn.strdisplaywidth(virt)
        if target_w > virt_w then
          virt = virt .. string.rep(' ', target_w - virt_w)
        end
        vim.api.nvim_buf_set_extmark(bufnr, exec_ns, line - 1, 0, {
          virt_text = { { virt, 'NvimTreeExecutableIcon' } },
          virt_text_win_col = padding_w,
          priority = 200,
        })
      end
    end
  end
end)

-- Overlay docker icon for files matching `Dockerfile.*` (Dockerfile.dev, .prod, etc.).
local docker_ns = vim.api.nvim_create_namespace('nvim_tree_docker_icon')
vim.api.nvim_set_hl(0, 'NvimTreeDockerIcon', { fg = require('config.theme_colors').blue })

require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  local bufnr = payload and payload.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, docker_ns, 0, -1)

  local core = require('nvim-tree.core')
  local explorer = core.get_explorer()
  if not explorer then return end

  local start_line = core.get_nodes_starting_line()
  local nodes_by_line = explorer:get_nodes_by_line(start_line)
  for line, node in pairs(nodes_by_line) do
    if node and node.type == 'file' and node.name and node.name:match('^Dockerfile%.') then
      local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''
      local name_byte = text:find(node.name, 1, true)
      if name_byte then
        local pre_name = text:sub(1, name_byte - 1)
        local icon_part = pre_name:gsub('^%s+', '')
        local padding_w = vim.fn.strdisplaywidth(pre_name) - vim.fn.strdisplaywidth(icon_part)
        local target_w = vim.fn.strdisplaywidth(icon_part)
        local virt = '\u{f21f}'
        local virt_w = vim.fn.strdisplaywidth(virt)
        if target_w > virt_w then
          virt = virt .. string.rep(' ', target_w - virt_w)
        end
        vim.api.nvim_buf_set_extmark(bufnr, docker_ns, line - 1, 0, {
          virt_text = { { virt, 'NvimTreeDockerIcon' } },
          virt_text_win_col = padding_w,
          priority = 200,
        })
      end
    end
  end
end)

-- Tint the folder expand arrow by name. Add name variations to a group's `names` list;
-- dot-folders fall back to brown by prefix. Colors the first non-blank token (the arrow).
local folder_ns = vim.api.nvim_create_namespace('nvim_tree_folder_color')
local folder_theme = require('config.theme_colors')

local folder_groups = {
  { hl = 'NvimTreeFolderSrcIcon',        color = folder_theme.blue,   names = { 'src' } },
  { hl = 'NvimTreeFolderTestsIcon',      color = folder_theme.green,  names = { 'tests' } },
  { hl = 'NvimTreeFolderCrateIcon',      color = folder_theme.purple, names = { 'crate', 'crates', 'module', 'modules' } },
  { hl = 'NvimTreeFolderMigrationsIcon', color = folder_theme.red,    names = { 'migrations', 'migrations_down' } },
  { hl = 'NvimTreeFolderDocsIcon',       color = folder_theme.yellow, names = { 'docs', 'spec', 'task' } },
  { hl = 'NvimTreeFolderFrontendIcon',   color = folder_theme.cyan,   names = { 'frontend' } },
  { hl = 'NvimTreeFolderDeployIcon',     color = folder_theme.orange, names = { 'deploy', 'nginx' } },
  { hl = 'NvimTreeFolderHiddenIcon',     color = folder_theme.brown,  names = {} }, -- dot-folders, matched by prefix below
}

-- Register each group's highlight and flatten its names into the lookup map.
local folder_arrow_hl = {}
for _, group in ipairs(folder_groups) do
  vim.api.nvim_set_hl(0, group.hl, { fg = group.color })
  for _, name in ipairs(group.names) do
    folder_arrow_hl[name] = group.hl
  end
end

require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  local bufnr = payload and payload.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, folder_ns, 0, -1)

  local core = require('nvim-tree.core')
  local explorer = core.get_explorer()
  if not explorer then return end

  local start_line = core.get_nodes_starting_line()
  local nodes_by_line = explorer:get_nodes_by_line(start_line)
  for line, node in pairs(nodes_by_line) do
    local hl = node and node.type == 'directory' and node.name
        and (folder_arrow_hl[node.name] or (node.name:sub(1, 1) == '.' and 'NvimTreeFolderHiddenIcon'))
    if hl then
      local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''
      local lead = text:match('^%s*')
      local arrow = text:sub(#lead + 1):match('^%S+')
      if arrow then
        vim.api.nvim_buf_set_extmark(bufnr, folder_ns, line - 1, #lead, {
          end_col = #lead + #arrow,
          hl_group = hl,
          priority = 200,
        })
      end
    end
  end
end)

-- Yellow bookmark dot in the signcolumn, mirroring how diagnostics mark the gutter.
-- A file in custom/bookmarks.lua's store gets one; so does any directory on the path to it.
local bookmark_ns = vim.api.nvim_create_namespace('nvim_tree_bookmark_sign')
-- Own group name; NvimTreeBookmarkIcon is nvim-tree's built-in marks sign.
vim.api.nvim_set_hl(0, 'NvimTreeUserBookmarkIcon', { fg = require('config.theme_colors').yellow })

local function place_bookmark_signs(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, bookmark_ns, 0, -1)

  local store = require('custom.bookmarks').store
  if not store or not next(store) then return end

  local explorer = require('nvim-tree.core').get_explorer()
  if not explorer then return end

  -- Marked when the node is a bookmarked file, or a directory holding one beneath it.
  local function has_bookmark(node)
    if not node or not node.absolute_path then return false end
    if node.type ~= 'directory' then return store[node.absolute_path] ~= nil end
    local prefix = node.absolute_path .. '/'
    for path in pairs(store) do
      if path:sub(1, #prefix) == prefix then return true end
    end
    return false
  end

  local start_line = require('nvim-tree.core').get_nodes_starting_line()
  for line, node in pairs(explorer:get_nodes_by_line(start_line)) do
    if has_bookmark(node) then
      vim.api.nvim_buf_set_extmark(bufnr, bookmark_ns, line - 1, 0, {
        sign_text = ' ' .. gutter_dot, -- leading space nudges the dot off the window edge into the 2nd gutter cell
        sign_hl_group = 'NvimTreeUserBookmarkIcon',
        priority = 5,                  -- below diagnostics (sign_place default 10) so hint/warn/error win the gutter cell
      })
    end
  end
end

-- nvim-tree defines its diagnostic signs with the glyph in the 1st gutter cell (hard against
-- the window edge); re-point them to ' ●' so they line up with the bookmark dot. It redefines
-- them every render, so we re-apply last, after place_bookmark_signs, on each TreeRendered.
local function align_diagnostic_signs()
  for _, name in ipairs({ 'Error', 'Warn', 'Info', 'Hint' }) do
    local hl = 'NvimTreeDiagnostic' .. name .. 'Icon'
    if not vim.tbl_isempty(vim.fn.sign_getdefined(hl)) then
      vim.fn.sign_define(hl, { text = ' ' .. gutter_dot, texthl = hl })
    end
  end
end

require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  place_bookmark_signs(payload and payload.bufnr)
  align_diagnostic_signs()
end)

-- Re-sign live when a bookmark is toggled, without a full tree reload (custom/bookmarks.lua
-- fires this after writing its store). Repaints only our namespace on the open tree buffer.
vim.api.nvim_create_autocmd('User', {
  pattern = 'BookmarksChanged',
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'NvimTree' then
        place_bookmark_signs(buf)
      end
    end
  end,
})

-- Auto-cd to project root based on common markers. nested = true so the global cd's
-- DirChanged reaches nvim-tree (sync_root_with_cwd), re-rooting the tree on project change.
vim.api.nvim_create_autocmd('BufEnter', {
  nested = true,
  callback = function(args)
    require('config.utils').auto_cd_to_project_root(args.buf)
  end,
})
