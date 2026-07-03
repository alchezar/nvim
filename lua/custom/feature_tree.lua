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

-- Match nvim-tree: its expander arrows + our folder icons.
local ARROW_CLOSED, ARROW_OPEN = '\u{F460}', '\u{F47C}'
local FOLDER_CLOSED, FOLDER_OPEN = '\u{F024B}', '\u{F0770}'
local ICON_PAD = '  ' -- match nvim-tree's icon padding

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
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_hl })
apply_hl()

-- A folder's aggregate takes the highest priority among its files (untracked > new > dirty).
local GIT_HL = { dirty = 'FeatureTreeGitDirty', new = 'FeatureTreeGitNew', untracked = 'FeatureTreeGitUntracked' }
local GIT_PRIORITY = { untracked = 3, new = 2, dirty = 1 }

M.collapsed = {} -- node key -> true; folded state persists across reopens
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

-- Per-file git state ('dirty'|'new'|'untracked') for the color overlay.
local function git_status(src)
  local dotgit = vim.fs.find('.git', { path = src, upward = true })[1]
  local root = dotgit and vim.fs.dirname(dotgit)
  if not root then return {} end
  local out = vim.fn.systemlist({ 'git', '-C', root, 'status', '--porcelain', '--no-renames' })
  if vim.v.shell_error ~= 0 then return {} end
  local map = {}
  for _, line in ipairs(out) do
    local code, rel = line:sub(1, 2), line:sub(4)
    local st = code == '??' and 'untracked'
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

-- Trie keyed by path within the layer, so per-layer variants of one feature merge into
-- a shared node. A node is { name, key, files = {{layer, path}}, children = { name -> node } }.
local function build_tree(src)
  local layers = real_layers(scan_layers(src))
  local root = { children = {} }
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

-- Trie -> buffer lines + per-line meta. No crate header: it's already in the statusline path.
local function render(root, status)
  local lines, hls, meta = {}, {}, {} -- meta: 1-indexed line -> node

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
      hl = GIT_HL[node_git(node, status)] or 'FeatureTreeFolderName'
    }
    meta[ln] = { kind = 'node', key = node.key }
    if not open then return end

    local find = ind + 6 -- files indent under the node
    local icon_prefix = FILE_ICON ~= '' and (FILE_ICON .. ICON_PAD) or ''
    table.sort(node.files, function(a, b) return a.layer < b.layer end)
    for _, f in ipairs(node.files) do
      local text = f.layer .. '.rs'
      lines[#lines + 1] = (' '):rep(find) .. icon_prefix .. text
      local fln = #lines
      if FILE_ICON ~= '' then
        hls[#hls + 1] = { line = fln - 1, col = find, len = #FILE_ICON, hl = FILE_ICON_HL }
      end
      hls[#hls + 1] = {
        line = fln - 1,
        col = find + #icon_prefix,
        len = #text,
        hl = GIT_HL[status[f.path]] or 'FeatureTreeFile'
      }
      meta[fln] = { kind = 'file', path = f.path, node = node.key }
    end
  end

  if FLAT_LAYOUT then
    for _, node in ipairs(flat_nodes(root)) do emit_line(node, 0, node.key) end
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

-- Unfold path's ancestors and return its line; repaint only if a fold actually opened. nil
-- when the path isn't a layer file of this crate.
local function reveal(state, path)
  if path == '' or path:sub(1, #state.src + 1) ~= state.src .. '/' then return end
  local rel = path:sub(#state.src + 2):match('^[^/]+/(.+%.rs)$')
  if not rel or rel == 'mod.rs' then return end -- non-layer file, or the layer-root mod.rs
  -- mod.rs keys to its dir (sync/mod.rs -> `sync`); other files just drop the extension.
  local key = rel:match('/mod%.rs$') and rel:sub(1, -8) or rel:sub(1, -4)
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

  local state = { buf = buf, win = win, src = src, root = root, status = git_status(src) }

  repaint(state) -- meta ready before `active` is published to follow
  active = state
  -- Drop the follow reference on any close (buffer is wipe-on-hide).
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function() if active and active.buf == buf then active = nil end end,
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

-- git status is a snapshot; refresh it on save/external-edit/commit while the panel is open.
local function status_changed(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return true end end
  for k, v in pairs(b) do if a[k] ~= v then return true end end
  return false
end

local refresh_timer
local function refresh_status()
  local st = active
  if not st or not st.win or not vim.api.nvim_win_is_valid(st.win) then return end
  local fresh = git_status(st.src)
  if status_changed(st.status, fresh) then
    st.status = fresh
    repaint(st)
  end
end

vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained', 'FileChangedShellPost' }, {
  callback = function()
    if not active then return end
    refresh_timer = refresh_timer or vim.uv.new_timer()
    if not refresh_timer then return end
    refresh_timer:stop()
    refresh_timer:start(150, 0, vim.schedule_wrap(refresh_status))
  end,
})

vim.api.nvim_create_user_command('FeatureTree', M.open, { desc = 'Feature view: transpose layer/feature tree' })

return M
