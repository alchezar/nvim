local M = {}

local colors = require('config.theme_colors')

-- Float yazi; open the chosen file.
function M.open_yazi()
  local tmp = vim.fn.tempname()
  local cwd = vim.fn.expand('%:p:h')
  if cwd == '' or vim.fn.isdirectory(cwd) == 0 then
    cwd = vim.fn.getcwd()
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local has_statusline = vim.o.laststatus > 0 and 1 or 0
  local editor_h = vim.o.lines - vim.o.cmdheight - has_statusline
  local height = math.floor(editor_h * 0.9)
  local width = math.floor(vim.o.columns * 0.9)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((editor_h - height - 2) / 2),
    col = math.floor((vim.o.columns - width - 2) / 2),
    style = 'minimal',
    border = 'rounded',
  })

  vim.fn.jobstart({ 'yazi', '--chooser-file=' .. tmp, cwd }, {
    term = true,
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
      local f = io.open(tmp, 'r')
      if not f then return end
      local path = f:read('*l')
      f:close()
      os.remove(tmp)
      if path and path ~= '' then
        vim.cmd('edit ' .. vim.fn.fnameescape(path))
      end
    end,
  })

  vim.cmd('startinsert')
end

-- Float lazygit. Geometry is shifted slightly up.
function M.open_lazygit()
  local cwd = vim.fn.expand('%:p:h')
  if cwd == '' or vim.fn.isdirectory(cwd) == 0 then
    cwd = vim.fn.getcwd()
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local has_statusline = vim.o.laststatus > 0 and 1 or 0
  local editor_h = vim.o.lines - vim.o.cmdheight - has_statusline
  local height = math.floor(editor_h * 0.9)
  local width = math.floor(vim.o.columns * 0.9)
  local row = math.max(0, math.floor(editor_h - height - 2) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = math.floor((vim.o.columns - width - 2) / 2),
    style = 'minimal',
    border = 'rounded',
  })

  vim.fn.jobstart({ 'lazygit' }, {
    cwd = cwd,
    term = true,
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
      vim.cmd('checktime')
    end,
  })

  vim.cmd('startinsert')
end

-- C/C++ source <-> header via clangd.
function M.switch_source_header()
  local clients = vim.lsp.get_clients({ bufnr = 0, name = 'clangd' })
  if #clients == 0 then
    vim.notify('clangd not attached', vim.log.levels.WARN)
    return
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  clients[1]:request('textDocument/switchSourceHeader',
    vim.lsp.util.make_text_document_params(0),
    function(err, result)
      if err then
        vim.notify('switchSourceHeader: ' .. tostring(err), vim.log.levels.ERROR)
        return
      end
      if not result then
        vim.notify('No matching source/header file', vim.log.levels.INFO)
        return
      end
      vim.cmd.edit(vim.uri_to_fname(result))
    end, 0)
end

function M.toggle_inlay_hints()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end

-- diagnostic.goto_prev/next are deprecated in 0.11; jump{count} replaces them.
function M.diagnostic_prev()
  vim.diagnostic.jump({ count = -1 })
end

function M.diagnostic_next()
  vim.diagnostic.jump({ count = 1 })
end

-- Break a one-line fn signature so each param sits on its own line.
-- Depth tracking keeps generics/tuples (Result<T, E>, (A, B)) intact.
local function split_signature(line)
  if not line:find('%f[%w]fn%f[%W]') then return nil end
  local open = line:find('(', 1, true)
  if not open then return nil end

  local depth, close = 0, nil
  for i = open, #line do
    local c = line:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
      if depth == 0 then
        close = i
        break
      end
    end
  end
  if not close then return nil end

  local inner = line:sub(open + 1, close - 1)
  if inner:gsub('%s', '') == '' then return nil end

  local params, last = {}, 1
  local a, b, c2, p = 0, 0, 0, 0 -- angle, bracket, brace, paren depth
  for i = 1, #inner do
    local ch = inner:sub(i, i)
    if ch == '<' then
      a = a + 1
    elseif ch == '>' then
      if a > 0 then a = a - 1 end
    elseif ch == '[' then
      b = b + 1
    elseif ch == ']' then
      if b > 0 then b = b - 1 end
    elseif ch == '{' then
      c2 = c2 + 1
    elseif ch == '}' then
      if c2 > 0 then c2 = c2 - 1 end
    elseif ch == '(' then
      p = p + 1
    elseif ch == ')' then
      if p > 0 then p = p - 1 end
    elseif ch == ',' and a == 0 and b == 0 and c2 == 0 and p == 0 then
      table.insert(params, inner:sub(last, i - 1))
      last = i + 1
    end
  end
  table.insert(params, inner:sub(last))
  if #params < 2 then return nil end

  local out = { line:sub(1, open) }
  for _, param in ipairs(params) do
    table.insert(out, '    ' .. vim.trim(param) .. ',')
  end
  table.insert(out, line:sub(close))
  return out
end

local function reflow_signatures(lines)
  local out = {}
  for _, l in ipairs(lines) do
    local split = split_signature(l)
    if split then vim.list_extend(out, split) else table.insert(out, l) end
  end
  return out
end

-- Hover float with line diagnostics prepended.
function M.hover()
  local bufnr = 0
  local lnum = vim.fn.line('.') - 1
  local diags = vim.diagnostic.get(bufnr, { lnum = lnum })

  local prefix = {}
  for _, d in ipairs(diags) do
    local sev = ({ 'ERROR', 'WARN', 'INFO', 'HINT' })[d.severity] or 'INFO'
    local src = d.source and (' (' .. d.source .. ')') or ''
    for i, msg_line in ipairs(vim.split(d.message, '\n', { plain = true })) do
      if i == 1 then
        table.insert(prefix, string.format('**[%s]**%s %s', sev, src, msg_line))
      else
        table.insert(prefix, msg_line)
      end
    end
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/hover' })
  local function show(lines)
    if #lines == 0 then return end
    vim.lsp.util.open_floating_preview(lines, 'markdown', {
      border = 'rounded',
      max_width = 80,
      focus_id = 'kinder-hover',
    })
  end

  if #clients == 0 then
    show(prefix)
    return
  end

  -- Query all hover clients; first non-empty wins (hybrid Vue: vue_ls returns null in <script>).
  local remaining = #clients
  local hover_lines = nil
  for _, client in ipairs(clients) do
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    client:request('textDocument/hover', params, function(err, result)
      if not hover_lines and not err and result and result.contents then
        local h = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
        if #h > 0 then hover_lines = reflow_signatures(h) end
      end
      remaining = remaining - 1
      if remaining == 0 then
        local lines = {}
        vim.list_extend(lines, prefix)
        if hover_lines then
          if #lines > 0 then table.insert(lines, '---') end
          vim.list_extend(lines, hover_lines)
        end
        show(lines)
      end
    end, bufnr)
  end
end

-- Preview a Rust file's leading `//!` module doc in a hover float (like `gh` on code).
-- Shared by nvim-tree and the feature-tree panel, so it takes a plain path.
function M.module_doc_float(path)
  local read_ok, file_lines = pcall(vim.fn.readfile, path, '', 100)
  if not read_ok then return end

  -- Collect the leading `//!` block, allowing blanks / attributes / other comments before it.
  local doc, started = {}, false
  for _, line in ipairs(file_lines) do
    local trimmed = vim.trim(line)
    local content = trimmed:match('^//!(.*)')
    if content then
      started = true
      table.insert(doc, (content:gsub('^ ', '')))
    elseif started or not (trimmed == '' or trimmed:match('^#!') or trimmed:match('^//')) then
      break
    end
  end

  if #doc == 0 then
    vim.notify('No //! module doc in ' .. vim.fn.fnamemodify(path, ':t'), vim.log.levels.INFO)
    return
  end
  vim.lsp.util.open_floating_preview(doc, 'markdown', {
    border = 'rounded',
    max_width = 80,
    focus_id = 'kinder-tree-doc',
  })
end

-- nvim-tree `gh`: hover the //! doc of the file under the cursor.
function M.tree_module_doc()
  local ok, api = pcall(require, 'nvim-tree.api')
  if not ok then return end
  local node = api.tree.get_node_under_cursor()
  if node and node.type == 'file' and node.absolute_path then M.module_doc_float(node.absolute_path) end
end

-- Jump to the trait method backing the symbol under cursor.
-- Plain LSP defn/decl misbehaves (inherent impls shadow, #[async_trait] -> ~/.cargo/registry).
function M.go_to_interface()
  local method_name = vim.fn.expand('<cword>')
  if method_name == '' then
    vim.notify('No word under cursor', vim.log.levels.WARN)
    return
  end
  local save_pos = vim.api.nvim_win_get_cursor(0)

  -- Find nearest `impl ... for ...` above cursor; skip inherent impls (no `for`).
  local impl_text
  for l = save_pos[1], 1, -1 do
    local text = vim.fn.getline(l)
    if text:match('^%s*impl[%s<].-%sfor%s') then
      impl_text = text
      break
    end
  end
  if not impl_text then
    vim.notify('Not inside an `impl Trait for ...` block', vim.log.levels.WARN)
    return
  end

  -- Extract trait name from "impl [<gens>] [path::]Trait[<gens>] for ...".
  local before_for = impl_text:match('^%s*impl%s+(.-)%s+for%s')
  if not before_for then
    vim.notify('Could not parse impl line: ' .. impl_text, vim.log.levels.WARN)
    return
  end
  before_for = before_for:gsub('^<[^>]+>%s+', '')
  local trait_name = before_for:match('([%w_]+)')
  if not trait_name then
    vim.notify('Could not extract trait name from: ' .. impl_text, vim.log.levels.WARN)
    return
  end

  local function jump_to_method_in_buffer(start_line)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    vim.fn.search('\\<fn\\s\\+' .. vim.fn.escape(method_name, '\\/') .. '\\>', 'cW')
  end

  -- Try current file first (common case: trait and impl colocated).
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local trait_line = vim.fn.search('\\v<trait>\\s+' .. trait_name .. '>', 'cW')
  if trait_line > 0 then
    jump_to_method_in_buffer(trait_line)
    return
  end

  -- Fall back to LSP workspace symbols (trait in another file).
  vim.api.nvim_win_set_cursor(0, save_pos)
  local clients = vim.lsp.get_clients({ bufnr = 0, method = 'workspace/symbol' })
  if #clients == 0 then
    vim.notify('trait `' .. trait_name .. '` not in current file; no workspace symbol LSP',
      vim.log.levels.WARN)
    return
  end
  clients[1]:request('workspace/symbol', { query = trait_name }, function(err, result)
    if err or not result or vim.tbl_isempty(result) then
      vim.notify('trait `' .. trait_name .. '` not found', vim.log.levels.WARN)
      return
    end
    -- Prefer exact name match of kind Interface (11) or Class (5).
    local target
    for _, sym in ipairs(result) do
      if sym.name == trait_name and (sym.kind == 11 or sym.kind == 5) then
        target = sym
        break
      end
    end
    target = target or result[1]
    local loc = target.location
    if not loc then
      vim.notify('Workspace symbol had no location', vim.log.levels.WARN)
      return
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(vim.uri_to_fname(loc.uri)))
    jump_to_method_in_buffer(loc.range.start.line + 1)
  end, 0)
end

-- Apply `tab_spaces` from the nearest rustfmt.toml.
function M.apply_rustfmt_indent(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then return end
  local found = vim.fs.find('rustfmt.toml', { upward = true, path = vim.fs.dirname(path) })[1]
  if not found then return end
  for line in io.lines(found) do
    local n = line:match('^%s*tab_spaces%s*=%s*(%d+)')
    if n then
      local sw                  = tonumber(n) --[[@as integer]]
      vim.bo[bufnr].shiftwidth  = sw
      vim.bo[bufnr].softtabstop = sw
      vim.bo[bufnr].tabstop     = sw
      return
    end
  end
end

function M.format()
  require('conform').format({ async = true, lsp_format = 'fallback' })
end

-- A restarted server's stale diagnostics linger in every OTHER buffer until it re-analyzes; clear
-- this client's push+pull namespaces (nvim.lsp.<name>.<id>[.<pull>]) across all buffers so phantom
-- errors vanish everywhere at once, not just the focused file.
local function reset_client_diagnostics(client_id, client_name)
  local prefix = ('nvim.lsp.%s.%d'):format(client_name, client_id)
  for ns_id, ns in pairs(vim.diagnostic.get_namespaces()) do
    if ns.name and (ns.name == prefix or vim.startswith(ns.name, prefix .. '.')) then
      vim.diagnostic.reset(ns_id) -- nil bufnr == all buffers
    end
  end
end

-- Stop all LSP clients on the buffer, wait for full exit, then re-fire FileType to re-attach.
-- With zero clients (server died / buffer detached on return) re-fire FileType to re-attach.
function M.restart_buf_lsp()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    if vim.bo[bufnr].buftype ~= '' or vim.bo[bufnr].filetype == '' then
      vim.notify('No LSP clients attached to this buffer', vim.log.levels.WARN)
      return
    end
    vim.notify('No LSP clients - re-attaching')
    vim.api.nvim_exec_autocmds('FileType', { buffer = bufnr, modeline = false })
    return
  end
  local names, ids = {}, {}
  for _, c in ipairs(clients) do
    table.insert(names, c.name)
    table.insert(ids, c.id)
    c:stop()
    reset_client_diagnostics(c.id, c.name) -- wipe phantom errors in every file, not just this one
  end
  vim.notify('Restarting LSP: ' .. table.concat(names, ', '))

  local function wait_and_reattach(attempt)
    for _, id in ipairs(ids) do
      if vim.lsp.get_client_by_id(id) then
        if attempt < 30 then
          vim.defer_fn(function() wait_and_reattach(attempt + 1) end, 100)
        else
          vim.notify('Timed out waiting for LSP to stop', vim.log.levels.WARN)
        end
        return
      end
    end
    vim.api.nvim_exec_autocmds('FileType', { buffer = bufnr, modeline = false })
  end
  wait_and_reattach(0)
end

-- Wipe the current buffer and reopen the same file, for a fully fresh buffer state.
-- A scratch buffer parks the window so the original can be force-wiped without closing it.
function M.reload_buf()
  local old = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(old)
  if name == '' or vim.bo[old].buftype ~= '' then
    vim.notify('Not a file buffer', vim.log.levels.WARN)
    return
  end
  if vim.bo[old].modified then
    vim.notify('Buffer has unsaved changes - save first', vim.log.levels.WARN)
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local scratch = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, scratch)
  vim.api.nvim_buf_delete(old, { force = true })
  vim.cmd('edit ' .. vim.fn.fnameescape(name))
  -- :edit reuses the empty scratch (loading the file into it); only wipe it
  -- when a separate buffer was opened instead, or we'd delete the reload.
  local cur = vim.api.nvim_get_current_buf()
  if cur ~= scratch and vim.api.nvim_buf_is_valid(scratch) then
    vim.api.nvim_buf_delete(scratch, { force = true })
  end
  pcall(vim.api.nvim_win_set_cursor, 0, pos)
end

-- Force nvim-tree to re-run git status. macOS fsevents can miss the atomic
-- .git/index rename-replace after external git ops, leaving stale/missing git
-- highlight in the tree; this re-reads the whole tree and its git state.
function M.reload_tree_git()
  local ok, api = pcall(require, 'nvim-tree.api')
  if not ok then
    vim.notify('nvim-tree not loaded', vim.log.levels.WARN)
    return
  end
  api.tree.reload()
  vim.notify('nvim-tree: git status reloaded', vim.log.levels.INFO)
end

-- Open a path from clipboard. Accepts `path`, `path:line`, `path:line:col`.
function M.open_clipboard_path()
  local raw = vim.trim(vim.fn.getreg('+'))
  local file, line, col = raw:match('^(.-):(%d+):(%d+)$')
  if not file then file, line = raw:match('^(.-):(%d+)$') end
  if not file then file = raw end
  file = vim.fn.expand(file)
  if vim.fn.filereadable(file) == 0 then
    vim.notify('File not found: ' .. file, vim.log.levels.WARN)
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(file))
  if line then
    vim.api.nvim_win_set_cursor(0, { tonumber(line), tonumber(col or 1) - 1 })
  end
end

function M.yank_to_clipboard(text)
  vim.fn.setreg('+', text)
  vim.notify('Copied: ' .. text)
end

function M.find_files_in_home()
  require('telescope.builtin').find_files({
    cwd = vim.env.HOME,
    hidden = true,
    no_ignore = true,
    prompt_title = 'Find files ($HOME)',
  })
end

-- Markers used by auto_cd_to_project_root.
M.project_root_markers = {
  '.git',
  'CMakeLists.txt',
  'Cargo.lock',
  'package.json',
  'pyproject.toml',
  'go.mod',
  '.clangd',
  'compile_commands.json',
}

-- Project root for a buffer by the markers above (nil if none / scratch buf).
function M.project_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.bo[bufnr].buftype ~= '' then return nil end
  return vim.fs.root(bufnr, M.project_root_markers)
end

-- Global cd (not lcd): a single cwd shared by all windows keeps nvim-tree's
-- root and its focus-reload check (getcwd == tree root) consistent. A window-local
-- lcd would diverge from the tree window's cwd and trigger a full reload on every focus.
function M.auto_cd_to_project_root(bufnr)
  local root = M.project_root(bufnr)
  if not root then
    -- No project marker: fall back to the file's own dir so the tree still follows it.
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= '' and vim.bo[bufnr].buftype == '' then
      root = vim.fs.dirname(path)
    end
  end
  if root and root ~= vim.fn.getcwd() then
    vim.cmd.cd(root)
  end
end

-- Resolve fg of the highlight under cursor.
local function cursor_color_at_pos()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local items = vim.inspect_pos(0, row, col)
  for _, list in ipairs({ items.semantic_tokens, items.treesitter, items.syntax, items.extmarks }) do
    for i = #list, 1, -1 do
      local entry = list[i]
      local name = entry.opts and entry.opts.hl_group or entry.hl_group
      if name then
        local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
        if hl.fg then return string.format('#%06x', hl.fg) end
      end
    end
  end
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  return normal.fg and string.format('#%06x', normal.fg) or colors.fg
end

-- Make Cursor inherit fg of the char under it.
function M.update_cursor_color()
  local fg = cursor_color_at_pos()
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local bg = normal.bg and string.format('#%06x', normal.bg) or colors.bg
  vim.api.nvim_set_hl(0, 'Cursor', { bg = fg, fg = bg })
end

-- Run SQL in the dbee editor (selection in visual mode, else statement under cursor).
-- dbee actions silently no-op without a connection; warn explicitly to avoid mystery hangs.
function M.dbee_run()
  local api = require('dbee').api
  if not api.core.get_current_connection() then
    vim.notify('Dbee: no active connection. Press <CR> on a connection node in the drawer.',
      vim.log.levels.WARN)
    return
  end
  local mode = vim.fn.mode()
  local action = (mode == 'v' or mode == 'V' or mode == '\22')
      and 'run_selection' or 'run_under_cursor'
  api.ui.editor_do_action(action)
  -- Result float starts hidden; un-hide after kicking off the query.
  pcall(function() require('plugins.dbee').show_result() end)
end

-- Jump straight to the feature-tree panel in the sidebar, if it's open.
function M.focus_feature_panel()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'FeatureTree' then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
  vim.notify('Feature panel is not open', vim.log.levels.INFO)
end

-- Toggle focus: normal -> first focusable float, float -> previous window.
function M.focus_floating()
  if vim.api.nvim_win_get_config(0).relative ~= '' then
    vim.cmd('wincmd p')
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative ~= '' and cfg.focusable ~= false then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  vim.notify('No floating window', vim.log.levels.INFO)
end

-- Gitsigns preview_hunk sizes the float to the longest line; clamp width and
-- soft-wrap so long hunks don't run off-screen.
function M.gitsigns_preview_hunk()
  local prior = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do prior[w] = true end

  require('gitsigns').preview_hunk()

  vim.schedule(function()
    local max_w = math.max(20, math.floor(vim.o.columns * 0.8))
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      -- Only the gitsigns popup, never the full-screen backdrop float that pops
      -- up alongside it (it is also "new" and wider than max_w).
      if not prior[win] and vim.w[win].gitsigns_preview ~= nil then
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative ~= '' and cfg.width and cfg.width > max_w then
          cfg.width = max_w
          vim.api.nvim_win_set_config(win, cfg)
          vim.api.nvim_set_option_value('wrap', true, { win = win })
          vim.api.nvim_set_option_value('linebreak', true, { win = win })
        end
      end
    end
  end)
end

-- Active keyboard layout, cached so the layout-aware keymaps below never shell
-- out on the hot path. A libuv timer refreshes it in the background (async
-- vim.system, non-blocking); polling pauses while nvim is unfocused.
local has_im_select = vim.fn.executable('im-select') == 1
local kbd_layout = ''
local function refresh_layout()
  if not has_im_select then return end
  vim.system({ 'im-select' }, { text = true }, function(r)
    if r.code == 0 then kbd_layout = vim.trim(r.stdout) end
  end)
end
local function on_ukrainian() return kbd_layout:find('Ukrainian', 1, true) ~= nil end

function M.watch_kbd_layout()
  if not has_im_select then return end
  local timer = vim.uv.new_timer()
  refresh_layout()
  if not timer then return end
  local function poll()
    if not timer:is_active() then timer:start(0, 300, vim.schedule_wrap(refresh_layout)) end
  end
  poll()
  vim.api.nvim_create_autocmd('FocusGained', {
    callback = function()
      refresh_layout(); poll()
    end
  })
  vim.api.nvim_create_autocmd('FocusLost', { callback = function() timer:stop() end })
end

-- These keys print the same char in both layouts but on different physical keys,
-- so langmap can't tell them apart. On Ukrainian the QWERTY-position command is
-- unreachable, so resolve to it; on any latin layout keep the key's own char.
function M.key_dollar() return on_ukrainian() and '$' or ';' end -- укр Shift+4 prints ;

function M.key_caret() return on_ukrainian() and '^' or ':' end  -- укр Shift+6 prints :

function M.key_at() return on_ukrainian() and '@' or '"' end     -- укр Shift+2 prints "

-- Search selection literally (\V) so regex metacharacters match as-is.
function M.search_visual(forward)
  vim.cmd('normal! "vy')
  local text = vim.fn.getreg('v')
  if text == '' then return end
  vim.fn.setreg('/', [[\V]] .. vim.fn.escape(text, [[\/]]))
  vim.cmd('normal! ' .. (forward and 'n' or 'N'))
end

-- Digits before gv are a native count (7<leader>gv -> HEAD~7). With none, prompt for a base:
-- a number is HEAD~N, other text is a branch, empty toggles off / falls back to origin/HEAD.
function M.branch_review_toggle()
  local br = require('custom.branch_review')
  local n = vim.v.count
  if n > 0 then return br.toggle('HEAD~' .. n) end
  vim.ui.input({ prompt = 'Review base (num=commits, text=branch): ' }, function(input)
    if input == nil then return end
    input = vim.trim(input)
    if input == '' then return br.toggle() end
    br.toggle(tonumber(input) and ('HEAD~' .. input) or input)
  end)
end

-- M.document_symbols kind column: palette color per kind, matching how the theme
-- paints each one in Rust code (see colors/kinder_theme.lua).
local SYMBOL_KIND_COLORS = {
  Function = 'green',
  Method = 'emerald',
  Constructor = 'emerald',
  Struct = 'blue',
  Class = 'blue',
  Object = 'blue',
  Interface = 'teal',
  TypeParameter = 'blue',
  Enum = 'cyan',
  EnumMember = 'pink',
  Field = 'gray',
  Property = 'gray',
  Constant = 'lime',
  Variable = 'white',
  Module = 'dark',
  Namespace = 'dark',
  Package = 'dark',
}
-- Markdown outline: H1..H6 in the colors markview paints them (plugins/markdown.lua).
local HEADING_COLORS = { 'red', 'orange', 'yellow', 'green', 'blue', 'purple' }

local function set_symbol_hl()
  vim.api.nvim_set_hl(0, 'TelescopeSymbolPublic', { fg = colors.green })
  vim.api.nvim_set_hl(0, 'TelescopeSymbolPrivate', { fg = colors.silver })
  vim.api.nvim_set_hl(0, 'TelescopeSymbolKindTest', { fg = colors.emerald })
  for kind, color in pairs(SYMBOL_KIND_COLORS) do
    vim.api.nvim_set_hl(0, 'TelescopeSymbolKind' .. kind, { fg = colors[color] --[[@as string]] })
  end
  for level, color in ipairs(HEADING_COLORS) do
    vim.api.nvim_set_hl(0, 'TelescopeSymbolHeading' .. level,
      { fg = colors[color] --[[@as string]], bold = true })
  end
end
set_symbol_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_symbol_hl })

-- Telescope stores the kind icon-prefixed; map that exact string to our hl group.
local symbol_kind_hl = {}
do
  local icons = require('config.lsp_icons').icons
  for kind in pairs(SYMBOL_KIND_COLORS) do
    symbol_kind_hl[(icons[kind] or '') .. kind] = 'TelescopeSymbolKind' .. kind
  end
end

-- Preview the live, LSP-attached buffer instead of a disk copy, so the code
-- keeps its real treesitter + semantic-token highlighting and diagnostics.
local function live_buffer_previewer(bufnr)
  return require('telescope.previewers').new({
    title = 'File structure',
    preview_fn = function(self, entry, status)
      local win = status.layout.preview and status.layout.preview.winid
      if not win or not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      self.state = self.state or {}
      self.state.winid = win
      if vim.api.nvim_win_get_buf(win) ~= bufnr then
        vim.api.nvim_win_set_buf(win, bufnr)
      end
      vim.wo[win].number, vim.wo[win].cursorline, vim.wo[win].wrap = true, true, false
      pcall(vim.api.nvim_win_set_cursor, win, { entry.lnum or 1, math.max((entry.col or 1) - 1, 0) })
      vim.api.nvim_win_call(win, function() vim.cmd('normal! zz') end)
    end,
    -- <C-d>/<C-u> scroll the preview via Ctrl-E/Ctrl-Y on its window.
    scroll_fn = function(self, direction)
      if not (self.state and self.state.winid) then return end
      local key = direction > 0 and '\5' or '\25'
      pcall(vim.api.nvim_win_call, self.state.winid, function()
        vim.cmd('normal! ' .. math.abs(direction) .. key)
      end)
    end,
    -- Telescope wipes whatever buffer sits in the preview window on close; swap
    -- the live buffer out for a scratch first so the real one survives.
    teardown = function(self)
      local win = self.state and self.state.winid
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_buf, win, vim.api.nvim_create_buf(false, true))
      end
    end,
  })
end

-- A #[test] / #[*::test] (sqlx, tokio, ...) attribute above a fn relabels its
-- kind column "test"; scan upward past attrs and doc comments to the real code.
local function fn_is_test(bufnr, lnum)
  for ln = lnum - 1, math.max(lnum - 15, 1), -1 do
    local trimmed = (vim.api.nvim_buf_get_lines(bufnr, ln - 1, ln, false)[1] or ''):match('^%s*(.-)%s*$')
    if trimmed == '' or trimmed:match('^//') then -- blank or comment: keep scanning
    elseif trimmed:match('^#!?%[') then
      local attr = trimmed:match('^#!?%[%s*([%w_:]+)')
      if attr and attr:match('[%w_]+$') == 'test' then return true end
    else
      return false -- hit real code before any test attr
    end
  end
  return false
end

-- rust-analyzer reports every fn as Function; ones sitting directly in an
-- impl/trait body are methods, so climb treesitter parents to tell them apart.
local function fn_is_method(bufnr, lnum, col)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { lnum - 1, col } })
  node = ok and node or nil
  while node do
    local t = node:type()
    if t == 'function_item' or t == 'function_signature_item' then
      local list = node:parent()
      local holder = list and list:parent()
      local ht = holder and holder:type()
      return ht == 'impl_item' or ht == 'trait_item'
    end
    node = node:parent()
  end
  return false
end

-- Land the picker on the symbol enclosing the cursor (greatest start line <=
-- the cursor) instead of the first row; runs once after results first load.
local function focus_symbol_at_cursor(opts)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local placed = false
  opts.on_complete = {
    function(picker)
      if placed then return end
      placed = true
      local best_index, best_lnum
      for index = 1, picker.manager:num_results() do
        local lnum = (picker.manager:get_entry(index) or {}).lnum
        if lnum and lnum <= cursor_line and (not best_lnum or lnum > best_lnum) then
          best_index, best_lnum = index, lnum
        end
      end
      if best_index then picker:set_selection(picker:get_row(best_index)) end
    end,
  }
end

-- Struct fields and enum variants swell the symbol list; hide them. Flip to true to show them.
local SHOW_MEMBERS = false

-- Markdown has no LSP here, so the outline is parsed out of the buffer itself.
local function markdown_outline(bufnr)
  local headings = require('custom.markdown_outline').headings(bufnr)
  if #headings == 0 then
    vim.notify('No headings in this buffer', vim.log.levels.INFO)
    return
  end
  local displayer = require('telescope.pickers.entry_display').create({
    separator = ' ',
    items = { { width = 5, right_justify = true }, { remaining = true } },
  })
  local opts = {}
  focus_symbol_at_cursor(opts)
  require('telescope.pickers').new(opts, {
    prompt_title = 'File structure',
    previewer = live_buffer_previewer(bufnr),
    sorter = require('telescope.config').values.generic_sorter(opts),
    finder = require('telescope.finders').new_table({
      results = headings,
      entry_maker = function(h)
        return {
          value = h,
          ordinal = h.text,
          lnum = h.lnum,
          col = 1,
          display = function(e)
            return displayer({
              { tostring(e.lnum),                           'TelescopeResultsLineNr' },
              { ('  '):rep(e.value.indent) .. e.value.text, 'TelescopeSymbolHeading' .. e.value.level },
            })
          end,
        }
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      require('telescope.actions').select_default:replace(function()
        local entry = require('telescope.actions.state').get_selected_entry()
        require('telescope.actions').close(prompt_bufnr)
        if entry then
          vim.api.nvim_win_set_cursor(0, { entry.lnum, 0 })
          vim.cmd('normal! zz')
        end
      end)
      return true
    end,
  }):find()
end

-- File structure (Telescope). Rust only: prefix each symbol with a visibility
-- marker read off the `pub` keyword on its source line.
function M.document_symbols()
  local builtin = require('telescope.builtin')
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype == 'markdown' then return markdown_outline(bufnr) end
  -- nil key = no filter; icon-prefixed kind name matches how lsp_icons patched it.
  local icons = require('config.lsp_icons').icons
  local ignore_symbols = SHOW_MEMBERS and nil
      or { icons.Field .. 'Field', icons.EnumMember .. 'EnumMember' }
  if vim.bo[bufnr].filetype ~= 'rust' then
    local opts = { previewer = live_buffer_previewer(bufnr), ignore_symbols = ignore_symbols }
    focus_symbol_at_cursor(opts)
    return builtin.lsp_document_symbols(opts)
  end
  -- Own displayer: line number first, then name, the visibility marker, and the kind column.
  local displayer = require('telescope.pickers.entry_display').create({
    separator = ' ',
    items = { { width = 5, right_justify = true }, { width = 60 }, { width = 2 }, { remaining = true } },
  })
  -- path_display hidden: every symbol lives in this one buffer, so drop the column.
  local opts = {
    bufnr = bufnr,
    path_display = { 'hidden' },
    previewer = live_buffer_previewer(bufnr),
    ignore_symbols =
        ignore_symbols
  }
  local default = require('telescope.make_entry').gen_from_lsp_symbols(opts)
  opts.entry_maker = function(line)
    local entry = default(line)
    if not entry then return entry end
    local src = vim.api.nvim_buf_get_lines(bufnr, entry.lnum - 1, entry.lnum, false)[1] or ''
    local pub = src:match('^%s*pub') ~= nil
    local icon = pub and '\u{ea70}' or '\u{eae7}' -- 󰈈 eye / 󰈉 eye-closed
    local hl = pub and 'TelescopeSymbolPublic' or 'TelescopeSymbolPrivate'
    -- symbol_type carries an icon prefix (lsp_icons patches SymbolKind), so match
    -- the trailing kind word and relabel "function" -> "test" / "method".
    local is_fn = entry.symbol_type:match('Function$') ~= nil
    local is_test = is_fn and fn_is_test(bufnr, entry.lnum)
    local is_method = is_fn and not is_test
        and fn_is_method(bufnr, entry.lnum, (src:find('%S') or 1) - 1)
    entry.display = function(e)
      local kind_col = is_test
          and { (e.symbol_type:lower():gsub('function$', 'test')), 'TelescopeSymbolKindTest' }
          or is_method
          and { icons.Method .. 'method', 'TelescopeSymbolKindMethod' }
          or { e.symbol_type:lower(), symbol_kind_hl[e.symbol_type] }
      return displayer({ { tostring(e.lnum), 'TelescopeResultsLineNr' }, e.symbol_name, { icon, hl }, kind_col })
    end
    return entry
  end
  focus_symbol_at_cursor(opts)
  builtin.lsp_document_symbols(opts)
end

-- Project-wide type declarations (struct/enum/trait/alias/class) via LSP. The
-- `symbols` filter must use icon-prefixed kind names since lsp_icons patches them.
function M.type_declarations()
  local icons = require('config.lsp_icons').icons
  local kinds = { 'Struct', 'Enum', 'Interface', 'TypeParameter', 'Class' }
  local symbols = vim.tbl_map(function(k) return icons[k] .. k end, kinds)
  -- Own displayer: symbol name, then its kind (palette-colored like document_symbols),
  -- then the file path last - so the name leads and the long path trails.
  local displayer = require('telescope.pickers.entry_display').create({
    separator = '  ',
    items = { { width = 50 }, { width = 18 }, { remaining = true } },
  })
  local opts = { symbols = symbols }
  local default = require('telescope.make_entry').gen_from_lsp_symbols(opts)
  opts.entry_maker = function(line)
    local entry = default(line)
    if not entry then return entry end
    entry.display = function(e)
      return displayer({
        e.symbol_name,
        { e.symbol_type:lower(),                                   symbol_kind_hl[e.symbol_type] },
        { vim.fn.fnamemodify(e.filename, ':~:.') .. ':' .. e.lnum, 'TelescopeResultsComment' },
      })
    end
    return entry
  end
  require('telescope.builtin').lsp_dynamic_workspace_symbols(opts)
end

-- One GitHub entry point: pick a snacks source for the current repo.
function M.github_menu()
  local picker = require('snacks').picker
  local items = {
    { label = 'Pull Requests', open = picker.gh_pr },
    { label = 'Issues',        open = picker.gh_issue },
  }
  vim.ui.select(items, {
    prompt = 'GitHub',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then choice.open() end
  end)
end

-- Neovide smears cursorline into ghost bands during smooth (touchpad) scroll. Hide cursorline
-- while a window is actively scrolling and restore it once scrolling settles. Only special
-- windows (tree, feature panel, blame - buftype ~= '') own a cursorline; normal file buffers
-- keep theirs off, so we never touch them and never freeze an inherited one on. Neovide-only.
function M.dim_cursorline_while_scrolling()
  local timers = {} -- winid -> reused uv debounce timer
  local hidden = {} -- winid -> true while we have hidden its cursorline
  vim.api.nvim_create_autocmd('WinScrolled', {
    callback = function()
      for id in pairs(vim.v.event) do
        local win = tonumber(id) -- keys are window ids (+ 'all', which tonumber drops)
        if win and vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          if hidden[win] or (vim.bo[buf].buftype ~= '' and vim.wo[win].cursorline) then
            vim.wo[win].cursorline = false
            hidden[win] = true
            timers[win] = timers[win] or vim.uv.new_timer()
            timers[win]:stop()
            timers[win]:start(180, 0, vim.schedule_wrap(function()
              hidden[win] = nil
              if not vim.api.nvim_win_is_valid(win) then return end
              -- Respect a window that asked to keep cursorline off (e.g. feature panel on a
              -- file not in its tree); don't restore it against that wish.
              local ok, suppressed = pcall(vim.api.nvim_win_get_var, win, 'ft_no_cursorline')
              if not (ok and suppressed) then vim.wo[win].cursorline = true end
            end))
          end
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function(args)
      local win = tonumber(args.match)
      if win and timers[win] then
        timers[win]:stop()
        timers[win]:close()
        timers[win], hidden[win] = nil, nil
      end
    end,
  })
end

-- git-diff tint for buffer names in the buffers picker: modified=blue, added=green,
-- untracked=red - same overlay as the feature tree. Re-applied on ColorScheme.
local BUF_GIT_HL = {
  dirty = 'TelescopeBufferGitDirty',
  new = 'TelescopeBufferGitNew',
  untracked = 'TelescopeBufferGitUntracked',
}
local function apply_buffer_git_hl()
  vim.api.nvim_set_hl(0, 'TelescopeBufferGitDirty', { fg = colors.blue })
  vim.api.nvim_set_hl(0, 'TelescopeBufferGitNew', { fg = colors.green })
  vim.api.nvim_set_hl(0, 'TelescopeBufferGitUntracked', { fg = colors.red })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_buffer_git_hl })
apply_buffer_git_hl()

-- Working-tree state ('dirty'|'new'|'untracked') per absolute path, from the cwd repo.
local function buffer_git_status()
  local dotgit = vim.fs.find('.git', { path = vim.uv.cwd(), upward = true })[1]
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
    if st then map[vim.fs.normalize(root .. '/' .. rel)] = st end
  end
  return map
end

-- builtin.buffers with each file name tinted by its git-diff state. Wraps the stock
-- entry_maker so the bufnr/flags/icon/path layout stays identical; only touched files recolor.
function M.buffers(opts)
  opts = opts or {}
  local telutils = require('telescope.utils')
  local strings = require('plenary.strings')
  local status = buffer_git_status()
  local icon_width = strings.strdisplaywidth((telutils.get_devicons('fname', opts.disable_devicons)))
  -- builtin.buffers merges pickers config into a *new* opts table before setting bufnr_width;
  -- our entry_maker closes over this one, so seed the width here or the displayer gets nil.
  local cur = vim.api.nvim_get_current_buf()
  local max_bufnr = 1
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.buflisted(b) == 1 and not (opts.ignore_current_buffer and b == cur) then
      max_bufnr = math.max(max_bufnr, b)
    end
  end
  opts.bufnr_width = opts.bufnr_width or #tostring(max_bufnr)
  local displayer -- built lazily on the first colored entry, once bufnr_width is known
  local default
  opts.entry_maker = function(element)
    default = default or require('telescope.make_entry').gen_from_buffer(opts)
    local entry = default(element)
    if not entry then return entry end
    local st = entry.path and status[vim.fs.normalize(entry.path)]
    if not st then return entry end -- unchanged files keep the stock display
    displayer = displayer or require('telescope.pickers.entry_display').create({
      separator = ' ',
      items = { { width = opts.bufnr_width }, { width = 4 }, { width = icon_width }, { remaining = true } },
    })
    entry.display = function(e)
      opts.__prefix = opts.bufnr_width + 4 + icon_width + 3 + 1 + #tostring(e.lnum)
      local name = telutils.transform_path(opts, e.filename)
      if not opts.disable_coordinates then name = name .. ':' .. e.lnum end
      local icon, icon_hl = telutils.get_devicons(e.filename, opts.disable_devicons)
      return displayer({
        { e.bufnr,     'TelescopeResultsNumber' },
        { e.indicator, 'TelescopeResultsComment' },
        { icon,        icon_hl },
        { name,        BUF_GIT_HL[st] },
      })
    end
    return entry
  end
  require('telescope.builtin').buffers(opts)
end

return M
