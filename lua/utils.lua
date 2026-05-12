local M = {}

-- Open yazi file manager in a floating terminal, edit the chosen file
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

-- Switch between C/C++ source and header file via clangd
function M.switch_source_header()
  local clients = vim.lsp.get_clients({ bufnr = 0, name = 'clangd' })
  if #clients == 0 then
    vim.notify('clangd not attached', vim.log.levels.WARN)
    return
  end
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

-- Toggle LSP inlay hints
function M.toggle_inlay_hints()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end

-- LSP hover with line diagnostics prepended (if any)
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

  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request('textDocument/hover', params, function(err, result)
    local lines = {}
    vim.list_extend(lines, prefix)
    if not err and result and result.contents then
      local hover = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
      if #hover > 0 then
        if #lines > 0 then table.insert(lines, '---') end
        vim.list_extend(lines, hover)
      end
    end
    show(lines)
  end, bufnr)
end

-- Go to the trait method that the current symbol implements.
-- Strategy: walk backward from the cursor to the enclosing `impl <Trait> for
-- <Type>` line, extract `<Trait>`, then locate `trait <Trait>` (first in the
-- current file, then via LSP workspace symbols), and finally scan forward in
-- that file for `fn <method_name>`. This avoids the corner cases of LSP
-- definition/declaration (inherent impls with the same method name shadowing
-- the trait method, #[async_trait] macros resolving to ~/.cargo/registry, ...).
function M.go_to_interface()
  local method_name = vim.fn.expand('<cword>')
  if method_name == '' then
    vim.notify('No word under cursor', vim.log.levels.WARN)
    return
  end
  local save_pos = vim.api.nvim_win_get_cursor(0)

  -- 1. Find the nearest `impl ... for ...` line above the cursor. Skip inherent
  -- impls (no `for`) - keep walking up.
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

  -- 2. Extract trait name from "impl [<gens>] [path::]Trait[<gens>] for ..."
  local before_for = impl_text:match('^%s*impl%s+(.-)%s+for%s')
  if not before_for then
    vim.notify('Could not parse impl line: ' .. impl_text, vim.log.levels.WARN)
    return
  end
  before_for = before_for:gsub('^<[^>]+>%s+', '')         -- strip `impl<G>`
  local trait_name = before_for:match('([%w_]+)')          -- first ident after gens
  if not trait_name then
    vim.notify('Could not extract trait name from: ' .. impl_text, vim.log.levels.WARN)
    return
  end

  -- Jump to `fn <method_name>` within a buffer, starting from `start_line`.
  local function jump_to_method_in_buffer(start_line)
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    vim.fn.search('\\<fn\\s\\+' .. vim.fn.escape(method_name, '\\/') .. '\\>', 'cW')
  end

  -- 3. Try the current file first - cheap and covers the common case where
  -- trait and impl live together.
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local trait_line = vim.fn.search('\\v<trait>\\s+' .. trait_name .. '>', 'cW')
  if trait_line > 0 then
    jump_to_method_in_buffer(trait_line)
    return
  end

  -- 4. Fall back to LSP workspace symbols (trait defined in another file).
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
    -- Prefer an exact name match of kind Interface (11) or Class (5).
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

-- Format current buffer via conform.nvim
function M.format()
  require('conform').format({ async = true, lsp_format = 'fallback' })
end

-- Stop all rust-analyzer clients, force rustaceanvim to respawn it on the
-- current buffer, and clear any stale diagnostics from the previous session.
function M.restart_rust_analyzer()
  for _, c in ipairs(vim.lsp.get_clients({ name = 'rust-analyzer' })) do
    vim.lsp.stop_client(c.id)
  end
  vim.notify('rust-analyzer restarting...')
  if vim.bo.filetype == 'rust' then
    vim.schedule(function() vim.cmd('edit') end)
  end
  vim.diagnostic.reset()
end

-- Open file path from system clipboard, supports `path`, `path:line`, `path:line:col`
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

-- Project root markers used to auto-cd into the project of the current buffer
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

-- Auto-cd to the detected project root when entering a buffer
function M.auto_cd_to_project_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or vim.bo[bufnr].buftype ~= '' then return end
  local root = vim.fs.root(bufnr, M.project_root_markers)
  if root and root ~= vim.fn.getcwd() then
    vim.cmd.lcd(root)
  end
end

-- Resolve the foreground color of the highlight at the cursor position
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
  return normal.fg and string.format('#%06x', normal.fg) or '#DCDCDC'
end

-- Update the Cursor highlight so the cursor takes the color of the char under it
function M.update_cursor_color()
  local fg = cursor_color_at_pos()
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local bg = normal.bg and string.format('#%06x', normal.bg) or '#262626'
  vim.api.nvim_set_hl(0, 'Cursor', { bg = fg, fg = bg })
end

return M
