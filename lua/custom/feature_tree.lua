-- Feature view for layer-based crates: transpose `layer/feature.rs` into a virtual
-- `feature/layer.rs` tree so all files of one feature sit together, without touching disk.
--   :FeatureTree / <leader>fv  split below nvim-tree; <CR> opens the real file, <Tab> folds
-- A "layer" is auto-detected: a first-level dir under src/ that shares at least one feature
-- path with another such dir (api/db/model), so bin/ and tests/ with unique names drop out.
-- Nested dirs are kept: db/templates/itinerary.rs shows as templates > itinerary > db.rs.

local theme = require('config.theme_colors')

local M = {}
local ns = vim.api.nvim_create_namespace('feature_tree')

-- true: flat rows with full path (templates/day); false: nested folder groups. Reopen to apply.
local FLAT_LAYOUT = true

-- true: fold a lone single-layer sub-feature (itineraries/duplicate.rs) into its parent as one
-- file named after the sub-feature (duplicate.rs), instead of a folder of its own. Reopen to apply.
local INLINE_SINGLETONS = true

-- true: gather top-level lone single-layer features (audit, auth, validators...) into one virtual
-- `root` folder, each labelled `<layer>/<feature>.rs`, instead of a folder apiece. Reopen to apply.
local GROUP_ROOT_SINGLETONS = true

-- Match nvim-tree: its expander arrows + our folder icons.
local ARROW_CLOSED, ARROW_OPEN = '\u{F460}', '\u{F47C}'
local FOLDER_CLOSED, FOLDER_OPEN = '\u{F024B}', '\u{F0770}'
local ICON_PAD = '  ' -- match nvim-tree's icon padding
local SEPARATOR_CHAR = '·' -- dotted rule between the real tree and this panel

-- .rs icon from devicons (same source as the tree); empty if unavailable.
local FILE_ICON, FILE_ICON_HL = '', 'FeatureTreeFile'
do
  local ok, dev = pcall(require, 'nvim-web-devicons')
  if ok then
    local ic, hl = dev.get_icon('x.rs', 'rs', { default = true })
    FILE_ICON, FILE_ICON_HL = ic or '', hl or 'FeatureTreeFile'
  end
end

-- Colors match the tree; git overlay reuses the diff palette. Re-applied on ColorScheme.
local function apply_hl()
  vim.api.nvim_set_hl(0, 'FeatureTreeArrow', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'FeatureTreeFolderName', { fg = theme.silver, bold = true })
  vim.api.nvim_set_hl(0, 'FeatureTreeFolderIcon', { fg = theme.silver })
  vim.api.nvim_set_hl(0, 'FeatureTreeFile', { fg = theme.gray })
  vim.api.nvim_set_hl(0, 'FeatureTreeGitDirty', { fg = theme.blue })
  vim.api.nvim_set_hl(0, 'FeatureTreeGitNew', { fg = theme.green })
  vim.api.nvim_set_hl(0, 'FeatureTreeGitUntracked', { fg = theme.red })
  vim.api.nvim_set_hl(0, 'FeatureTreeGitRenamed', { fg = theme.yellow })
  -- Branch-review overlay, matching the real tree's BranchReviewFile/Folder.
  vim.api.nvim_set_hl(0, 'FeatureTreeReviewFile', { fg = theme.purple, bold = true })
  vim.api.nvim_set_hl(0, 'FeatureTreeReviewFolder', { fg = theme.purple })
  -- Dotted rule splitting the panel off the tree; WinSeparator itself is bg-on-bg (invisible).
  vim.api.nvim_set_hl(0, 'FeatureTreeSeparator', { fg = theme.dark })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })
apply_hl()

-- A folder's aggregate takes the highest priority among its files (untracked > new > renamed > dirty).
local GIT_HL = {
  dirty = 'FeatureTreeGitDirty',
  new = 'FeatureTreeGitNew',
  untracked = 'FeatureTreeGitUntracked',
  renamed = 'FeatureTreeGitRenamed',
}
local GIT_PRIORITY = { untracked = 4, new = 3, renamed = 2, dirty = 1 }

M.collapsed = {} -- node key -> true (folded). Re-seeded on open: clean folders fold, changed stay open.
local active     -- open panel's state, for the follow/refresh autocmds; nil when closed

-- Nearest crate's src/, walking up to its Cargo.toml.
---@return string? src_dir, string? crate_name
local function crate_src(bufnr)
  local start = vim.api.nvim_buf_get_name(bufnr)
  if start == '' then start = vim.fn.getcwd() end
  local cargo = vim.fs.find('Cargo.toml', { path = start, upward = true })[1]
  if not cargo then return nil end
  local dir = vim.fs.dirname(cargo)
  local src = dir .. '/src'
  if vim.fn.isdirectory(src) == 0 then return nil end
  return src, vim.fs.basename(dir)
end

-- Per-file git state ('dirty'|'new'|'untracked'|'renamed') for the color overlay. Renames are
-- detected (like nvim-tree) and keyed at the new path, so a moved file gets its own color instead
-- of a spurious green 'new' from the added half of a delete+add pair.
local function git_status(src)
  local dotgit = vim.fs.find('.git', { path = src, upward = true })[1]
  local root = dotgit and vim.fs.dirname(dotgit)
  if not root then return {} end
  local out = vim.fn.systemlist({ 'git', '-C', root, 'status', '--porcelain' })
  if vim.v.shell_error ~= 0 then return {} end
  local map = {}
  for _, line in ipairs(out) do
    local code, rel = line:sub(1, 2), line:sub(4)
    local s, e = rel:find(' %-> ') -- rename shows `old -> new`; the file now lives at new
    if s then rel = rel:sub(e + 1) end
    local st = code == '??' and 'untracked'
        or (code:find('R') and 'renamed')
        or (code:find('A') and 'new')
        or (code:find('[MDC]') and 'dirty')
        or nil
    if st then map[root .. '/' .. rel] = st end
  end
  return map
end

-- Files keyed by path within the layer (no ext). mod.rs is the dir's own module: it keys to its
-- containing dir (sync/mod.rs -> `sync`), so a feature dir shows across layers. The layer-root
-- mod.rs (api/mod.rs, empty prefix) is the layer itself, not a feature - skip it.
local function scan_layer(dir, prefix, out)
  for name, ty in vim.fs.dir(dir) do
    if ty == 'directory' then
      scan_layer(dir .. '/' .. name, prefix .. name .. '/', out)
    elseif ty == 'file' and name:match('%.rs$') then
      if name == 'mod.rs' then
        if prefix ~= '' then out[prefix:sub(1, -2)] = dir .. '/' .. name end
      else
        out[prefix .. name:sub(1, -4)] = dir .. '/' .. name
      end
    end
  end
end

-- First-level src/ subdirs, each with its feature files.
local function scan_layers(src)
  local layers = {}
  for name, ty in vim.fs.dir(src) do
    if ty == 'directory' then
      local files = {}
      scan_layer(src .. '/' .. name, '', files)
      if next(files) then layers[name] = files end
    end
  end
  return layers
end

-- A layer must share a feature with another (api/db/model); this drops standalone dirs like
-- bin/. Fall back to all dirs if nothing intersects, so the view is never empty.
local function real_layers(layers)
  local seen, shared = {}, {}
  for layer, files in pairs(layers) do
    for key in pairs(files) do
      if seen[key] then
        shared[layer] = true
        shared[seen[key]] = true
      else
        seen[key] = layer
      end
    end
  end
  if not next(shared) then return layers end
  local out = {}
  for layer in pairs(shared) do out[layer] = layers[layer] end
  return out
end

-- Fold a lone single-layer sub-feature (itineraries/duplicate.rs) into its parent as one file
-- labelled `<layer>/<feature>` (api/duplicate), so it shows its layer without earning its own
-- folder. Multi-layer or non-leaf sub-features keep their node; top-level singles too (root has no
-- key, grouped later). Leaf-ness is tested before recursing, so a fold never cascades up a chain.
local function inline_singletons(node)
  for name, child in pairs(node.children) do
    if next(child.children) == nil and #child.files == 1 and node.key then
      local f = child.files[1]
      node.files[#node.files + 1] = { layer = f.layer, path = f.path, label = f.layer .. '/' .. name }
      node.children[name] = nil
    else
      inline_singletons(child)
    end
  end
end

-- Sorts last (0xFF byte) so the catch-all folder sinks to the tree's bottom; never a real path key.
local ROOT_GROUP_KEY = '\255root'

-- Gather top-level lone single-layer features (a leaf with one file, directly under root) into one
-- virtual `root` folder, each file labelled `<layer>/<feature>` so its layer stays visible. Stops
-- the tree sprouting a folder per orphan. Runs after inline, so parents that absorbed a singleton
-- now carry >1 file and are correctly left alone.
local function group_root_singletons(root)
  local group
  for name, child in pairs(root.children) do
    if next(child.children) == nil and #child.files == 1 then
      -- display: shown in the flat layout instead of key, whose 0xFF sort byte renders as <ff>.
      group = group or { name = 'root', key = ROOT_GROUP_KEY, display = 'root', files = {}, children = {} }
      local f = child.files[1]
      group.files[#group.files + 1] = { layer = f.layer, path = f.path, label = f.layer .. '/' .. name }
      root.children[name] = nil
    end
  end
  if group then root.children[ROOT_GROUP_KEY] = group end -- added after the loop, not mid-iteration
end

-- Trie keyed by path within the layer, so per-layer variants of one feature merge into
-- a shared node. A node is { name, key, files = {{layer, path, label?}}, children = { name -> node } }.
local function build_tree(src)
  local layers = real_layers(scan_layers(src))
  local root = { children = {}, files = {} } -- files=[] keeps the shape uniform for owner_key's walk
  for layer, files in pairs(layers) do
    for key, path in pairs(files) do
      local node, prefix = root, ''
      for comp in key:gmatch('[^/]+') do
        prefix = prefix == '' and comp or (prefix .. '/' .. comp)
        node.children[comp] = node.children[comp] or { name = comp, key = prefix, files = {}, children = {} }
        node = node.children[comp]
      end
      node.files[#node.files + 1] = { layer = layer, path = path }
    end
  end
  if INLINE_SINGLETONS then inline_singletons(root) end
  if GROUP_ROOT_SINGLETONS then group_root_singletons(root) end
  return root
end

-- Groups (dirs) before leaves, alphabetical - like a file tree.
local function sorted_children(node)
  local kids = {}
  for _, child in pairs(node.children) do kids[#kids + 1] = child end
  table.sort(kids, function(a, b)
    local ga, gb = next(a.children) ~= nil, next(b.children) ~= nil
    if ga ~= gb then return ga end
    return a.name < b.name
  end)
  return kids
end

-- Leaf nodes (those with files) by full key, for the flat layout.
local function flat_nodes(root)
  local out = {}
  local function walk(node)
    if node.key and #node.files > 0 then out[#out + 1] = node end
    for _, child in pairs(node.children) do walk(child) end
  end
  walk(root)
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

-- Aggregate git state of a node's subtree, for the folder color.
local function node_git(node, status)
  local best
  local function bump(s)
    if s and (not best or GIT_PRIORITY[s] > GIT_PRIORITY[best]) then best = s end
  end
  for _, f in ipairs(node.files) do bump(status[f.path]) end
  for _, child in pairs(node.children) do bump(node_git(child, status)) end
  return best
end

-- Seed folds on (re)open: collapse folders whose subtree is git-clean, leave changed ones open, so a
-- clean diff starts fully folded. Caller resets M.collapsed first; reveals/unfolds then only ever open.
local function seed_folds(node, status)
  for _, child in pairs(node.children) do
    if not node_git(child, status) then M.collapsed[child.key] = true end
    seed_folds(child, status)
  end
end

-- Branch-review state (custom/branch_review), or nil when the module is absent or review is off.
-- Loaded lazily on first paint so feature_tree doesn't force it at startup. Its `changed` set is
-- keyed by the same absolute paths as git_status, so f.path lookups match directly.
local review_mod
local function get_review()
  if review_mod == nil then
    local ok, m = pcall(require, 'custom.branch_review')
    review_mod = ok and m or false
  end
  return review_mod or nil
end

-- Any file under this node changed since the review base?
local function node_reviewed(node, changed)
  for _, f in ipairs(node.files) do
    if changed[f.path] then return true end
  end
  for _, child in pairs(node.children) do
    if node_reviewed(child, changed) then return true end
  end
  return false
end

-- Trie -> buffer lines + per-line meta. No crate header: it's already in the statusline path.
local function render(root, status)
  local lines, hls, meta = {}, {}, {} -- meta: 1-indexed line -> node
  local review = get_review()
  if review and not review.active then review = nil end -- overlay only while review is on

  -- One node row + its files. label = bare name (nested) or full key (flat). Caller recurses.
  local function emit_line(node, depth, label)
    local ind = 2 * (depth + 1) -- depth 0 at col 2
    local open = not M.collapsed[node.key]
    local arrow = open and ARROW_OPEN or ARROW_CLOSED
    local folder = open and FOLDER_OPEN or FOLDER_CLOSED
    lines[#lines + 1] = ('%s%s %s%s%s'):format((' '):rep(ind), arrow, folder, ICON_PAD, label)
    local ln = #lines
    local name_col = ind + #arrow + 1 + #folder + #ICON_PAD
    hls[#hls + 1] = { line = ln - 1, col = ind, len = #arrow, hl = 'FeatureTreeArrow' }
    hls[#hls + 1] = { line = ln - 1, col = ind + #arrow + 1, len = #folder, hl = 'FeatureTreeFolderIcon' }
    hls[#hls + 1] = {
      line = ln - 1,
      col = name_col,
      len = #label,
      hl = (review and node_reviewed(node, review.changed) and 'FeatureTreeReviewFolder')
          or GIT_HL[node_git(node, status)] or 'FeatureTreeFolderName'
    }
    meta[ln] = { kind = 'node', key = node.key }
    if not open then return end

    local find = ind + 6 -- files indent under the node
    local icon_prefix = FILE_ICON ~= '' and (FILE_ICON .. ICON_PAD) or ''
    -- Real layer files first (by layer), then folded-in singletons (by name).
    table.sort(node.files, function(a, b)
      if (a.label ~= nil) ~= (b.label ~= nil) then return a.label == nil end
      return (a.label or a.layer) < (b.label or b.layer)
    end)
    for _, f in ipairs(node.files) do
      local text = (f.label or f.layer) .. '.rs'
      lines[#lines + 1] = (' '):rep(find) .. icon_prefix .. text
      local fln = #lines
      if FILE_ICON ~= '' then
        hls[#hls + 1] = { line = fln - 1, col = find, len = #FILE_ICON, hl = FILE_ICON_HL }
      end
      hls[#hls + 1] = {
        line = fln - 1,
        col = find + #icon_prefix,
        len = #text,
        hl = (review and review.changed[f.path] and 'FeatureTreeReviewFile')
            or GIT_HL[status[f.path]] or 'FeatureTreeFile'
      }
      meta[fln] = { kind = 'file', path = f.path, node = node.key }
    end
  end

  if FLAT_LAYOUT then
    for _, node in ipairs(flat_nodes(root)) do emit_line(node, 0, node.display or node.key) end
  else
    local function emit(node, depth)
      emit_line(node, depth, node.name)
      if not M.collapsed[node.key] then
        for _, child in ipairs(sorted_children(node)) do emit(child, depth + 1) end
      end
    end
    for _, child in ipairs(sorted_children(root)) do emit(child, 0) end
  end
  if #lines == 0 then -- nothing emitted: crate has no layered features
    local note = '(no layered features)'
    lines[1] = '  ' .. note
    hls[#hls + 1] = { line = 0, col = 2, len = #note, hl = 'FeatureTreeFile' }
    meta[1] = { kind = 'blank' }
  end
  return lines, hls, meta
end

-- Redraw in place so the cursor keeps its position.
local function repaint(state)
  local lines, hls, meta = render(state.root, state.status)
  state.meta = meta
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, h.line, h.col, {
      end_col = h.col + h.len,
      hl_group = h.hl,
    })
  end
end

-- Tab window showing filetype ft, or nil.
local function win_by_ft(ft)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == ft then return w end
  end
end

-- An editing window (not tree/panel) to open files into.
local function edit_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
    if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == '' and ft ~= 'FeatureTree' and ft ~= 'NvimTree' then
      return w
    end
  end
end

-- The rule between the trees is the hsep *under* the tree window, so it's drawn with the tree's own
-- fillchars and WinSeparator - not ours. Swap both there while the panel is up, restore on close.
local function set_separator(tree_win, on)
  if not (tree_win and vim.api.nvim_win_is_valid(tree_win)) then return end
  local fc = vim.opt.fillchars:get() -- start from the global blanks, override just horiz
  fc.horiz = on and SEPARATOR_CHAR or ' '
  vim.api.nvim_win_call(tree_win, function() vim.opt_local.fillchars = fc end)
  local wh = vim.wo[tree_win].winhighlight
  vim.wo[tree_win].winhighlight = wh:gsub('WinSeparator:%w+',
    'WinSeparator:' .. (on and 'FeatureTreeSeparator' or 'NvimTreeWinSeparator'))
end

local function close(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
end

-- Open the file under the cursor in the editing window; keep the panel.
local function open_file(state)
  local node = state.meta[vim.api.nvim_win_get_cursor(state.win)[1]]
  if not node then return end
  if node.kind == 'node' then
    M.collapsed[node.key] = not M.collapsed[node.key]
    repaint(state)
    return
  end
  if node.kind ~= 'file' then return end
  local target = edit_win()
  if target then
    vim.api.nvim_set_current_win(target)
  else
    -- Only the sidebar is open: carve an editing window to its right.
    vim.api.nvim_set_current_win(state.win)
    vim.cmd('wincmd l')
  end
  vim.cmd.edit(vim.fn.fnameescape(node.path))
end

local function toggle_fold(state)
  local node = state.meta[vim.api.nvim_win_get_cursor(state.win)[1]]
  local key = node and (node.kind == 'node' and node.key or node.node)
  if not key then return end
  M.collapsed[key] = not M.collapsed[key]
  repaint(state)
end

-- Hover the file-under-cursor's //! module doc in a float, like `gh` on code / in nvim-tree.
local function module_doc(state)
  local node = state.meta[vim.api.nvim_win_get_cursor(state.win)[1]]
  if node and node.kind == 'file' then require('config.utils').module_doc_float(node.path) end
end

-- Every node key in the trie, for fold-all / unfold-all.
local function all_keys(node, acc)
  for _, child in pairs(node.children) do
    acc[child.key] = true
    all_keys(child, acc)
  end
  return acc
end

local function set_all_folds(state, folded)
  for key in pairs(all_keys(state.root, {})) do
    M.collapsed[key] = folded or nil
  end
  repaint(state)
end

-- Buffer line of path (normalized so symlinks/../ match), or nil.
local function line_of_path(state, path)
  path = vim.fs.normalize(path)
  for lnum, node in pairs(state.meta) do
    if node.kind == 'file' and vim.fs.normalize(node.path) == path then return lnum end
  end
end

-- Key of the node whose files include `path` (normalized); nil if no node owns it. Walks the actual
-- trie, so inlined/grouped files resolve to their real owner rather than their on-disk path.
local function owner_key(node, path)
  for _, f in ipairs(node.files) do
    if vim.fs.normalize(f.path) == path then return node.key end
  end
  for _, child in pairs(node.children) do
    local k = owner_key(child, path)
    if k then return k end
  end
end

-- Unfold the owning node's ancestors and return path's line; repaint only if a fold actually
-- opened. nil when the path isn't a file of this crate's tree.
local function reveal(state, path)
  if path == '' then return end
  path = vim.fs.normalize(path)
  local key = owner_key(state.root, path)
  if not key then return end
  local changed, prefix = false, ''
  for comp in key:gmatch('[^/]+') do
    prefix = prefix == '' and comp or (prefix .. '/' .. comp)
    if M.collapsed[prefix] then
      M.collapsed[prefix] = nil
      changed = true
    end
  end
  if changed then repaint(state) end
  return line_of_path(state, path)
end

-- Fingerprint of the tree's shape (owner keys + file paths), to spot files added/removed/renamed
-- on disk without diffing node-by-node.
local function tree_sig(node)
  local acc = {}
  local function walk(n)
    for _, f in ipairs(n.files) do acc[#acc + 1] = (n.key or '') .. '=' .. f.path end
    for _, c in pairs(n.children) do walk(c) end
  end
  walk(node)
  table.sort(acc)
  return table.concat(acc, '\n')
end

-- Toggle a panel split below nvim-tree: real file tree on top, virtual feature tree below.
function M.open()
  local existing = win_by_ft('FeatureTree')
  if existing then
    vim.api.nvim_win_close(existing, true)
    return
  end

  -- Crate from the edited file, not the focused window (may be the tree).
  local ew = edit_win()
  local ctx_buf = ew and vim.api.nvim_win_get_buf(ew) or vim.api.nvim_get_current_buf()
  local src = crate_src(ctx_buf)
  if not src then
    vim.notify('Feature tree: no Cargo.toml with a src/ above this file', vim.log.levels.WARN)
    return
  end
  local root = build_tree(src)
  if not next(root.children) then
    vim.notify('Feature tree: no layered files found under ' .. src, vim.log.levels.WARN)
    return
  end

  -- Split the tree window; open the sidebar first if closed.
  local tree_win = win_by_ft('NvimTree')
  if not tree_win then
    require('nvim-tree.api').tree.open()
    tree_win = win_by_ft('NvimTree')
  end
  if not tree_win then
    vim.notify('Feature tree: could not open the file tree to split', vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'FeatureTree'

  local col_height = vim.api.nvim_win_get_height(tree_win) -- column height before split, for 1/3 sizing
  vim.api.nvim_set_current_win(tree_win)
  vim.cmd('belowright split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].cursorline = true
  vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].signcolumn = false, false, 'no'
  vim.wo[win].winfixheight = true
  vim.wo[win].list = false -- no listchars, like the tree

  set_separator(tree_win, true)

  local state = {
    buf = buf, win = win, tree_win = tree_win,
    src = src, root = root, status = git_status(src), sig = tree_sig(root),
  }

  M.collapsed = {} -- fresh window: fold clean folders, keep changed ones open
  seed_folds(root, state.status)
  repaint(state) -- meta ready before `active` is published to follow
  active = state
  -- Drop the follow reference on any close (buffer is wipe-on-hide) and un-dot the tree's edge.
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      set_separator(state.tree_win, false)
      if active and active.buf == buf then active = nil end
    end,
  })

  -- Land on the currently edited file; else the first feature.
  local target = reveal(state, ctx_buf and vim.api.nvim_buf_get_name(ctx_buf) or '')
  pcall(vim.api.nvim_win_set_height, win, math.floor(col_height / 3)) -- 1/3 panel, 2/3 tree
  vim.api.nvim_win_set_cursor(win, { target or 1, 0 })
  if target then vim.api.nvim_win_call(win, function() vim.cmd('normal! zz') end) end

  local kmap = function(lhs, fn) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true }) end
  kmap('<CR>', function() open_file(state) end)
  kmap('o', function() open_file(state) end)
  kmap('<2-LeftMouse>', function() open_file(state) end) -- double-click opens, like the tree
  kmap('gh', function() module_doc(state) end)
  kmap('<Tab>', function() toggle_fold(state) end)
  kmap('za', function() toggle_fold(state) end)
  kmap('zM', function() set_all_folds(state, true) end)
  kmap('zR', function() set_all_folds(state, false) end)
  kmap('q', function() close(state) end)
end

-- Follow the editor: move the panel cursor onto the opened file, without stealing focus.
local function follow(bufnr)
  local st = active
  if not st or not st.win or not vim.api.nvim_win_is_valid(st.win) then return end
  if vim.bo[bufnr].buftype ~= '' then return end -- ignore tree/panel/scratch
  local path = vim.api.nvim_buf_get_name(bufnr)

  -- Different crate: rebuild for it (a crate with no layers renders empty, not stale).
  if path ~= '' and path:sub(1, #st.src + 1) ~= st.src .. '/' then
    local src = crate_src(bufnr)
    if src and src ~= st.src then
      st.src, st.root, st.status = src, build_tree(src), git_status(src)
      st.sig = tree_sig(st.root)
      M.collapsed = {} -- new crate == new tree: re-seed folds
      seed_folds(st.root, st.status)
      repaint(st)
    end
  end

  local target = reveal(st, path)
  -- Flag the window so the scroll-dim timer won't re-light cursorline we hid on purpose.
  vim.api.nvim_win_set_var(st.win, 'ft_no_cursorline', target == nil)
  if target then
    vim.wo[st.win].cursorline = true
    vim.api.nvim_win_set_cursor(st.win, { target, 0 })
    vim.api.nvim_win_call(st.win, function() vim.cmd('normal! zz') end)
  else
    vim.wo[st.win].cursorline = false -- not in the tree: a highlight would be stale
  end
end

vim.api.nvim_create_autocmd('BufEnter', { callback = function(args) follow(args.buf) end })

-- Branch review toggled on/off: recolor the panel to match the real tree (no structure change).
vim.api.nvim_create_autocmd('User', {
  pattern = 'BranchReviewChanged',
  callback = function() if active then repaint(active) end end,
})

-- git status is a snapshot; refresh it on save/external-edit/commit while the panel is open.
local function status_changed(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return true end end
  for k, v in pairs(b) do if a[k] ~= v then return true end end
  return false
end

-- Rebuild both structure (files added/removed/renamed) and git colors; repaint only on real change.
local function refresh()
  local st = active
  if not st or not st.win or not vim.api.nvim_win_is_valid(st.win) then return end
  local root = build_tree(st.src)
  local sig, status = tree_sig(root), git_status(st.src)
  if sig ~= st.sig or status_changed(st.status, status) then
    st.root, st.sig, st.status = root, sig, status
    repaint(st)
  end
end

local refresh_timer
local function schedule_refresh()
  if not active then return end
  refresh_timer = refresh_timer or vim.uv.new_timer()
  if not refresh_timer then return end
  refresh_timer:stop()
  refresh_timer:start(150, 0, vim.schedule_wrap(refresh))
end

vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained', 'FileChangedShellPost' }, {
  callback = schedule_refresh,
})

-- nvim-tree emits these when it creates/removes/renames on disk (keys a/d/r) and when its
-- filesystem watcher catches external changes; mirror the change into our tree.
do
  local ok_api, tree_api = pcall(require, 'nvim-tree.api')
  if ok_api then
    for _, ev in ipairs({ 'FileCreated', 'FileRemoved', 'FolderCreated', 'FolderRemoved', 'NodeRenamed' }) do
      pcall(function() tree_api.events.subscribe(tree_api.events.Event[ev], schedule_refresh) end)
    end
  end
end

vim.api.nvim_create_user_command('FeatureTree', M.open, { desc = 'Feature view: transpose layer/feature tree' })

return M
