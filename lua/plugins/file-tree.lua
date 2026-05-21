-- nvim-tree: file explorer sidebar
-- Keymaps live in lua/keys.lua (<leader>e/E/f, <D-S-e>)

-- Natural (humanized) comparator: splits names into text/number runs and
-- compares number chunks numerically, so `9` sorts before `10`. Without
-- this, nvim-tree falls back to lexicographic order (`10, 11, ..., 4, 9`).
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

-- Custom sorter: directories first, then case-insensitive natural sort.
-- When `sort.sorter` is a function, nvim-tree delegates ordering entirely
-- to it (its built-in `folders_first` is bypassed), so handle that here.
local function tree_sorter(nodes)
  table.sort(nodes, function(a, b)
    if a.type ~= b.type then
      if a.type == 'directory' then return true end
      if b.type == 'directory' then return false end
    end
    -- Pin landmark files to the top of their directory (after subfolders):
    -- `README.md` first (case-insensitive), then `mod.rs` (Rust module entry).
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
  sync_root_with_cwd = true,
  respect_buf_cwd = true,
  sort = { sorter = tree_sorter },
  view = { width = 40, cursorline = false },
  update_focused_file = {
    enable = true,
    update_root = {
      enable = true,
      ignore_list = {},
    },
  },
  root_dirs = {},
  git = { enable = true },
  filters = {
    git_ignored = false,
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
      padding = '  ',
      show = { git = false },
      glyphs = {
        folder = {
          default    = '\u{F07B}',  -- nf-fa-folder (closed, filled) for non-empty
          open       = '\u{F115}',  -- nf-fa-folder_open_o (matches yazi theme)
          empty      = '\u{F114}',  -- nf-fa-folder_o (outline) for empty closed
          empty_open = '\u{F115}',
        },
      },
    },
  },
})

-- Tree highlight overrides: dim gitignored items, neutral gray for folders.
local function apply_tree_hl()
  local theme = require('config.theme_colors')
  -- Gitignored stays a darker gray
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileIgnoredHL',   { fg = theme.dark })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderIgnoredHL', { fg = theme.dark })
  -- Modified (dirty) git files/folders -> blue (matches GitSignsChange)
  vim.api.nvim_set_hl(0, 'NvimTreeGitFileDirtyHL',     { fg = theme.blue })
  vim.api.nvim_set_hl(0, 'NvimTreeGitFolderDirtyHL',   { fg = theme.blue })
  -- Folders neutral gray (was theme blue by default)
  vim.api.nvim_set_hl(0, 'NvimTreeFolderName',        { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'NvimTreeOpenedFolderName',  { fg = theme.gray, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTreeEmptyFolderName',   { fg = theme.gray, italic = true })
  vim.api.nvim_set_hl(0, 'NvimTreeFolderIcon',        { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'NvimTreeOpenedFolderIcon',  { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'NvimTreeRootFolder',        { fg = theme.gray, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTreeSymlinkFolderName', { fg = theme.gray, italic = true })
  -- Subtle cursor line in the tree only (NvimTreeCursorLine is mapped via winhl)
  vim.api.nvim_set_hl(0, 'NvimTreeCursorLine', { bg = theme.black })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_tree_hl })
apply_tree_hl()

-- Annotate `mod.rs` and `README.md` (case-insensitive) entries with their
-- parent directory name, e.g. `mod.rs  [transactions]`. Useful in deep
-- trees where several such entries would otherwise be indistinguishable.
-- Implemented via extmarks on the tree buffer, refreshed after every render.
local mod_ns = vim.api.nvim_create_namespace('nvim_tree_mod_rs_parent')
vim.api.nvim_set_hl(0, 'NvimTreeModRsParent', { fg = require('config.theme_colors').gray })

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
      -- Only annotate when the entry sits below sibling subdirectories.
      -- Without subdirs it's already the first entry, so the parent name
      -- is obvious from the row directly above.
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

-- Enable cursorline only inside the tree window. Use both events: FileType
-- catches first-open (BufWinEnter fires before filetype is set), and
-- BufWinEnter handles re-opens. Targeting the specific window showing the
-- buffer avoids relying on `vim.wo` of whichever window happens to be
-- current when the event fires.
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

-- When nvim-tree opens a file via `o` (or any split-from-tree path), the new
-- editor window inherits `cursorline = true` from the NvimTree window since
-- `cursorline` is window-local and copied on :split. Strip it from regular
-- file windows. Skipped while a blame view is active in the tab - blame.nvim
-- legitimately needs cursorline on its synced editor window.
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
