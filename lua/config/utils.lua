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

-- Stop all LSP clients on the buffer, wait for full exit, then re-fire FileType to re-attach.
function M.restart_buf_lsp()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    vim.notify('No LSP clients attached to this buffer', vim.log.levels.WARN)
    return
  end
  local names, ids = {}, {}
  for _, c in ipairs(clients) do
    table.insert(names, c.name)
    table.insert(ids, c.id)
    c:stop()
  end
  vim.notify('Restarting LSP: ' .. table.concat(names, ', '))
  vim.diagnostic.reset(nil, bufnr)

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
      if not prior[win] then
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

-- A count reviews the last N commits (7<leader>gv -> HEAD~7); no count toggles the whole branch.
function M.branch_review_toggle()
  local n = vim.v.count
  require('custom.branch_review').toggle(n > 0 and ('HEAD~' .. n) or nil)
end

return M
