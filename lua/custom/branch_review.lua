-- Branch review mode: see everything changed since the branch forked from its base
-- (committed + working + untracked), not just the working tree. Toggle :ReviewMode [base].
--   gutter signs  - gitsigns base switched to the fork point, so committed branch changes
--                   show as hunks in normal buffers; no diff window, no line backgrounds.
--   tree marks    - changed file names tinted; a folder holding a change is tinted too,
--                   so a change inside a collapsed dir is still visible.
-- Base defaults to origin/HEAD (then main/master). Override with a branch (:ReviewMode dev),
-- a count (7<leader>gv = last 7 commits), or a commit hash to review up to and including it
-- (:ReviewMode 5628b47 == N<leader>gv when that hash is the Nth commit back from HEAD).

local theme = require('config.theme_colors')

local M = {}
local ns = vim.api.nvim_create_namespace('branch_review_tree')

M.active = false
---@type table<string, true>
M.changed = {} -- set: absolute path -> true, for every path that differs from the base

vim.api.nvim_set_hl(0, 'BranchReviewFile', { fg = theme.purple, bold = true })
vim.api.nvim_set_hl(0, 'BranchReviewFolder', { fg = theme.purple })

-- Runs in the global cwd, which is the project root, so relative paths resolve against it.
local function git(args)
  local out = vim.fn.systemlist(vim.list_extend({ 'git' }, args))
  if vim.v.shell_error ~= 0 then return nil end
  return out
end

local function repo_root()
  local out = git({ 'rev-parse', '--show-toplevel' })
  return out and out[1] ~= '' and out[1] or nil
end

-- origin/HEAD points at the remote default branch; fall back to a local main/master.
local function default_base()
  local out = git({ 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' })
  if out and out[1] and out[1] ~= '' then return out[1] end
  for _, b in ipairs({ 'main', 'master' }) do
    if git({ 'rev-parse', '--verify', '--quiet', b }) then return b end
  end
  return nil
end

-- Resolve the fork point and collect every path differing from it.
---@return { sha: string, set: table<string, true> }? result, string? err
local function compute(base)
  local root = repo_root()
  if not root then return nil, 'not a git repository' end
  local mb = git({ 'merge-base', base, 'HEAD' })
  if not mb or not mb[1] then return nil, 'no merge-base with ' .. base end
  local set = {}
  for _, rel in ipairs(git({ 'diff', '--name-only', mb[1] }) or {}) do
    set[root .. '/' .. rel] = true
  end
  for _, rel in ipairs(git({ 'ls-files', '--others', '--exclude-standard' }) or {}) do
    set[root .. '/' .. rel] = true
  end
  return { sha = mb[1], set = set }
end

-- Map a user argument to the exclusive diff base, plus a label for messages.
--   branch / remote ref / relative notation (dev, origin/main, HEAD~4) - used as-is;
--   a bare commit-ish (a hash) means "review up to and including it", so its parent is the base.
local function resolve_base(arg)
  if arg:find('[~^]') then return arg, arg end
  for _, prefix in ipairs({ 'refs/heads/', 'refs/remotes/' }) do
    if git({ 'show-ref', '--verify', '--quiet', prefix .. arg }) then return arg, arg end
  end
  return arg .. '^', arg
end

-- A folder is marked when any changed path lives beneath it.
local function dir_has_change(node)
  local prefix = node.absolute_path .. '/'
  for path in pairs(M.changed) do
    if path:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function paint(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not M.active then return end

  local core = require('nvim-tree.core')
  local explorer = core.get_explorer()
  if not explorer then return end

  for line, node in pairs(explorer:get_nodes_by_line(core.get_nodes_starting_line())) do
    if node and node.absolute_path and node.name then
      local hl
      if node.type == 'directory' then
        if dir_has_change(node) then hl = 'BranchReviewFolder' end
      elseif M.changed[node.absolute_path] then
        hl = 'BranchReviewFile'
      end
      if hl then
        local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''
        local s = text:find(node.name, 1, true)
        if s then
          vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, s - 1, {
            end_col = s - 1 + #node.name,
            hl_group = hl,
            priority = 300, -- above nvim-tree's own git/name highlight
          })
        end
      end
    end
  end
end

local function repaint_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'NvimTree' then
      paint(buf)
    end
  end
  -- Let other panels (feature_tree) recolor to the new review state.
  vim.api.nvim_exec_autocmds('User', { pattern = 'BranchReviewChanged', modeline = false })
end

-- Re-apply on every tree render so the marks survive reloads.
require('nvim-tree.api').events.subscribe('TreeRendered', function(payload)
  paint(payload and payload.bufnr)
end)

-- No base while active = turn off. A base (explicit or default) turns on / re-snapshots.
function M.toggle(base)
  local gs = require('gitsigns')
  if M.active and not base then
    M.active, M.changed = false, {}
    gs.change_base(nil, true)
    repaint_all()
    vim.notify('Branch review off', vim.log.levels.INFO)
    return
  end

  base = base or default_base()
  if not base or base == '' then
    vim.notify('Branch review: no base branch found - pass one, e.g. :ReviewMode dev', vim.log.levels.WARN)
    return
  end

  local diff_base, label = resolve_base(base)
  local result, err = compute(diff_base)
  if not result then
    vim.notify('Branch review: ' .. tostring(err), vim.log.levels.WARN)
    return
  end

  M.active, M.changed = true, result.set
  gs.change_base(result.sha, true)
  repaint_all()
  local n = vim.tbl_count(result.set)
  vim.notify(('Branch review vs %s - %d changed file%s'):format(label, n, n == 1 and '' or 's'), vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('ReviewMode', function(opts)
  M.toggle(opts.args ~= '' and opts.args or nil)
end, { nargs = '?', desc = 'Toggle branch review vs a branch/ref, or up to & including a commit hash' })

return M
