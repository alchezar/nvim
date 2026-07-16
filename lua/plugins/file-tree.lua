-- nvim-tree: file explorer sidebar. Keymaps in lua/keys.lua.

-- Gutter sign glyphs for diagnostics and bookmarks. Filled dot marks the node that carries
-- the marker; hollow dot marks the folders containing it. Glyph alts: ◆ ■ ▰ ▸ ◉ ⬤ • ◦
local file_dot = '●'
local dir_dot = '○'

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
  -- Keep nvim-tree's default maps, but route `s` to EasyMotion 2-char search like everywhere else
  -- (its built-in buffer-local `s` would otherwise shadow the global mapping).
  on_attach = function(bufnr)
    local api = require('nvim-tree.api')
    api.config.mappings.default_on_attach(bufnr)
    vim.keymap.set('n', 's', '<Plug>(easymotion-s2)', { buffer = bufnr, desc = 'EasyMotion 2-char search' })
    -- Match `gh`-on-code: hover the file's //! module doc in a float.
    vim.keymap.set('n', 'gh', require('config.utils').tree_module_doc, { buffer = bufnr, desc = 'Module //! doc' })
  end,
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
  -- 400ms default is too tight here: a slow startup git status disables integration for the session.
  git = { enable = true, timeout = 2000 },
  filesystem_watchers = { enable = true },

  filters = {
    -- Show git-ignored files (.env, .secret/...): nvim-tree runs `git status --ignored=matching`,
    -- which does NOT recurse into ignored dirs, so this is cheap. Hide only the huge target/.
    git_ignored = false,
    custom = { '^target$', '^\\.DS_Store$' },
  },
  diagnostics = {
    enable = true,
    show_on_dirs = true, -- keeps get_diag_status returning severity for folders; we draw the signs
  },
  renderer = {
    highlight_git = 'name',
    highlight_diagnostics = 'name',
    icons = {
      -- nvim-tree docs type padding as string; bundled stub says table -> false positive.
      ---@diagnostic disable-next-line: assign-type-mismatch
      padding = '  ',
      show = { git = false, diagnostics = false }, -- diagnostic signs drawn manually (file vs folder glyph)
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
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileIgnoredHL', { fg = theme.teal })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderIgnoredHL', { fg = theme.teal })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileDirtyHL', { fg = theme.blue })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderDirtyHL', { fg = theme.blue })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileRenamedHL', { fg = theme.yellow })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderRenamedHL', { fg = theme.yellow })
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

-- nvim-tree paints via extmarks, never vim-syntax; a stray syntax (e.g. 'rust'
-- inherited on buffer reuse) would light up keyword-like names (the `mod` in mod.rs).
require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  local bufnr = payload and payload.bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].syntax ~= '' then
    vim.bo[bufnr].syntax = ''
  end
end)

-- Annotate mod.rs / README.md with `[parent]`, and `foo.rs` next to `foo/` with `[mod]`.
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
    -- Module declared as a sibling file: `custom.rs` next to a `custom/` dir.
    if node and node.name and node.name ~= 'mod.rs' and node.name:match('%.rs$')
        and node.parent and node.parent.nodes then
      local stem = node.name:sub(1, -4) -- strip '.rs'
      for _, sibling in ipairs(node.parent.nodes) do
        if sibling.type == 'directory' and sibling.name == stem then
          vim.api.nvim_buf_set_extmark(bufnr, mod_ns, line - 1, 0, {
            virt_text = { { '[mod]', 'NvimTreeModRsParent' } },
            virt_text_pos = 'eol',
          })
          break
        end
      end
    end

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
  { hl = 'NvimTreeFolderHiddenIcon',     color = folder_theme.teal,   names = {} }, -- dot-folders, matched by prefix below
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

-- Bookmark dot in the signcolumn, mirroring how diagnostics mark the gutter. A file
-- in custom/bookmarks.lua's store gets one, as does any directory on the path to it;
-- cyan when only letter marks are in scope, yellow when a numbered/plain mark is too.
local bookmark_ns = vim.api.nvim_create_namespace('nvim_tree_bookmark_sign')
-- Own group name; NvimTreeBookmarkIcon is nvim-tree's built-in marks sign.
-- Re-applied on ColorScheme: :colorscheme runs :hi clear, else the dot greys out.
local function apply_bookmark_hl()
  local theme = require('config.theme_colors')
  vim.api.nvim_set_hl(0, 'NvimTreeUserBookmarkIcon', { fg = theme.yellow })
  -- Letter-only dot tracks the buffer a-z sign color (one source in bookmarks.lua).
  vim.api.nvim_set_hl(0, 'NvimTreeUserBookmarkLetterIcon', { fg = require('custom.bookmarks').letter_color })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_bookmark_hl })
apply_bookmark_hl()

local function place_bookmark_signs(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, bookmark_ns, 0, -1)

  local store = require('custom.bookmarks').store
  if not store or not next(store) then return end

  local explorer = require('nvim-tree.core').get_explorer()
  if not explorer then return end

  -- All records are letter marks (a-z/A-Z); numbered and plain marks aren't.
  local function all_letters(recs)
    for _, rec in ipairs(recs) do
      if type(rec.group) ~= 'string' or not rec.group:match('^%a$') then return false end
    end
    return true
  end

  -- Dot color for a node, or nil when it carries no bookmark. A file or the
  -- directory above it goes cyan only when every bookmark in scope is a letter
  -- mark; any numbered/plain mark makes it yellow.
  local function dot_hl(node)
    if not node or not node.absolute_path then return nil end
    if node.type ~= 'directory' then
      local recs = store[node.absolute_path]
      if not recs then return nil end
      return all_letters(recs) and 'NvimTreeUserBookmarkLetterIcon' or 'NvimTreeUserBookmarkIcon'
    end
    local prefix = node.absolute_path .. '/'
    local found, letters_only = false, true
    for path, recs in pairs(store) do
      if path:sub(1, #prefix) == prefix then
        found = true
        if not all_letters(recs) then letters_only = false end
      end
    end
    if not found then return nil end
    return letters_only and 'NvimTreeUserBookmarkLetterIcon' or 'NvimTreeUserBookmarkIcon'
  end

  local start_line = require('nvim-tree.core').get_nodes_starting_line()
  for line, node in pairs(explorer:get_nodes_by_line(start_line)) do
    local hl = dot_hl(node)
    if hl then
      local glyph = node.type == 'directory' and dir_dot or file_dot
      vim.api.nvim_buf_set_extmark(bufnr, bookmark_ns, line - 1, 0, {
        sign_text = ' ' .. glyph, -- leading space nudges the dot off the window edge into the 2nd gutter cell
        sign_hl_group = hl,
        priority = 5,             -- below diagnostics (priority 10) so hint/warn/error win the gutter cell
      })
    end
  end
end

-- Diagnostic gutter signs drawn by us (renderer's own are off): a folder containing a
-- diagnostic gets the hollow dot, the offending file the filled one. Color reuses nvim-tree's.
local diag_ns = vim.api.nvim_create_namespace('nvim_tree_diag_sign')
local diag_hl = {
  [vim.diagnostic.severity.ERROR] = 'NvimTreeDiagnosticErrorIcon',
  [vim.diagnostic.severity.WARN]  = 'NvimTreeDiagnosticWarnIcon',
  [vim.diagnostic.severity.INFO]  = 'NvimTreeDiagnosticInfoIcon',
  [vim.diagnostic.severity.HINT]  = 'NvimTreeDiagnosticHintIcon',
}

local function place_diagnostic_signs(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, diag_ns, 0, -1)

  local diagnostics = require('nvim-tree.diagnostics')
  local core = require('nvim-tree.core')
  local explorer = core.get_explorer()
  if not explorer then return end

  for line, node in pairs(explorer:get_nodes_by_line(core.get_nodes_starting_line())) do
    local status = node and diagnostics.get_diag_status(node)
    local severity = status and status.value
    if severity then
      local glyph = node.type == 'directory' and dir_dot or file_dot
      vim.api.nvim_buf_set_extmark(bufnr, diag_ns, line - 1, 0, {
        sign_text = ' ' .. glyph, -- leading space mirrors the bookmark dot's 2nd-cell placement
        sign_hl_group = diag_hl[severity] or 'NvimTreeDiagnosticErrorIcon',
        priority = 10,            -- above bookmarks (5) so a diagnostic wins a shared gutter cell
      })
    end
  end
end

require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  local bufnr = payload and payload.bufnr
  place_diagnostic_signs(bufnr)
  place_bookmark_signs(bufnr)
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
