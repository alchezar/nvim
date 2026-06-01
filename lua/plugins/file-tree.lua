-- nvim-tree: file explorer sidebar. Keymaps in lua/keys.lua.

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
      hint = '●',
      info = '●',
      warning = '●',
      error = '●',
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
          default    = '\u{F07B}',
          open       = '\u{F115}',
          empty      = '\u{F114}',
          empty_open = '\u{F115}',
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

-- Auto-cd to project root based on common markers. nested = true so the global cd's
-- DirChanged reaches nvim-tree (sync_root_with_cwd), re-rooting the tree on project change.
vim.api.nvim_create_autocmd('BufEnter', {
  nested = true,
  callback = function(args)
    require('config.utils').auto_cd_to_project_root(args.buf)
  end,
})
