-- Telescope picker for axum/utoipa endpoints. A `// METHOD /full/path` comment
-- above #[utoipa::path(..)] supplies the full URL; bare attrs get (no prefix).

local M            = {}

local pickers      = require('telescope.pickers')
local finders      = require('telescope.finders')
local conf         = require('telescope.config').values
local actions      = require('telescope.actions')
local action_state = require('telescope.actions.state')

local METHODS      = 'GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|TRACE'
local METHOD_LIST  = { 'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS', 'TRACE' }

local function rg_vimgrep(pattern, extra_args, paths)
  local cmd = { 'rg', '--vimgrep', '--no-heading', '--color=never',
    '--type', 'rust', '-i' }
  for _, a in ipairs(extra_args or {}) do table.insert(cmd, a) end
  table.insert(cmd, '-e'); table.insert(cmd, pattern)
  for _, p in ipairs(paths or {}) do table.insert(cmd, p) end
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 and #out == 0 then return {} end
  return out
end

local function parse_vimgrep(line)
  local file, lnum, col, text = line:match('^(.-):(%d+):(%d+):(.*)$')
  if not file then return nil end
  return { file = file, lnum = tonumber(lnum), col = tonumber(col), text = text }
end

-- Forward-scan for `fn name`, then walk back through attributes/blanks to grab
-- the topmost `///` line - this is the summary utoipa picks up.
local function find_handler_after(file, start_lnum, span)
  local lines = vim.fn.readfile(file, '', start_lnum + span)
  local name, fn_lnum
  for i = start_lnum + 1, math.min(#lines, start_lnum + span) do
    local l = lines[i]
    local n = l:match('^%s*pub%s+async%s+fn%s+([%w_]+)')
        or l:match('^%s*pub%s+fn%s+([%w_]+)')
        or l:match('^%s*pub%([^)]+%)%s+async%s+fn%s+([%w_]+)')
        or l:match('^%s*pub%([^)]+%)%s+fn%s+([%w_]+)')
        or l:match('^%s*async%s+fn%s+([%w_]+)')
        or l:match('^%s*fn%s+([%w_]+)')
    if n then
      name, fn_lnum = n, i; break
    end
  end
  if not name then return nil, nil, nil end

  local doc, in_doc, in_attr
  local i = fn_lnum - 1
  while i >= 1 and fn_lnum - i <= span do
    local l = lines[i]
    if l:match('^%s*///') then
      in_doc = true
      local content = l:match('^%s*///+!?%s*(.*)$') or ''
      content = content:gsub('%s+$', '')
      if content ~= '' then doc = content end
    elseif in_doc then
      break
    elseif l:match('^%s*$') then
      -- blank, keep scanning
    elseif l:match('%)%]%s*$') or l:match('^%s*%]%s*$') then
      in_attr = true
    elseif in_attr then
      if l:match('^%s*#%[') then in_attr = false end
    elseif l:match('^%s*#%[.*%]%s*$') then
      -- self-contained single-line attribute
    else
      break
    end
    i = i - 1
  end
  return name, fn_lnum, doc
end

-- Keywords that end the attribute block by starting the documented item.
local ITEM_KW = {
  fn = true, struct = true, enum = true, union = true, trait = true,
  impl = true, type = true, const = true, static = true, mod = true, use = true,
}

-- First keyword of a line, ignoring visibility/async/unsafe/default modifiers.
local function first_kw(l)
  local s = l:gsub('^%s*', '')
  s = s:gsub('^pub%s*%b()%s*', ''):gsub('^pub%s+', '')
  s = s:gsub('^default%s+', ''):gsub('^unsafe%s+', ''):gsub('^async%s+', '')
  return s:match('^([%w_]+)')
end

-- A banner counts only when a `#[utoipa::path(` attribute sits between it and
-- the item it documents. Scan down through blanks/comments/other attributes
-- (`#[inline]` etc); stop at the first declaration. utoipa first -> handler;
-- a declaration first -> it documents a type/overview, so reject it.
local function anchor_over_utoipa(file, anchor_lnum)
  local lines = vim.fn.readfile(file, '', anchor_lnum + 120)
  for i = anchor_lnum + 1, math.min(#lines, anchor_lnum + 120) do
    local l = lines[i]
    if l:match('^%s*#%[utoipa::path') then return true end
    local w = first_kw(l)
    if w and ITEM_KW[w] then return false end
  end
  return false
end

local function collect_anchored(file)
  -- Match `METHOD /path` anywhere in a `//`/`///` comment - covers bare
  -- `// GET /x`, doc `/// GET /x`, and banners `// Foo - GET /x`. Skip tests/
  -- only on a project-wide scan; a single explicit file is always searched.
  local pattern = [[^\s*//.*\b(]] .. METHODS .. [[)\s+/]]
  local extra = file and {} or { '-g', '!**/tests/**' }
  local paths = file and { file } or nil
  local out, seen = {}, {}
  for _, raw in ipairs(rg_vimgrep(pattern, extra, paths)) do
    local m = parse_vimgrep(raw)
    -- `//!` lines are module-level endpoint overviews - they duplicate the
    -- per-handler `///` and resolve to the wrong fn, so drop them.
    if m and not m.text:match('^%s*//!') and anchor_over_utoipa(m.file, m.lnum) then
      local meth, path
      for _, mm in ipairs(METHOD_LIST) do
        local p = m.text:match(mm .. '%s+`?(/[^`%s),]*)')
        if p then
          meth, path = mm, p; break
        end
      end
      if meth and path then
        local handler, hlnum, doc = find_handler_after(m.file, m.lnum, 120)
        local key = hlnum and (m.file .. ':' .. hlnum) or (meth .. ' ' .. path)
        if not seen[key] then
          seen[key] = true
          table.insert(out, {
            method       = meth,
            path         = path,
            file         = m.file,
            anchor_lnum  = m.lnum,
            handler      = handler,
            handler_lnum = hlnum,
            doc          = doc,
            kind         = 'anchor',
          })
        end
      end
    end
  end
  return out
end

local function collect_utoipa(file)
  local paths = file and { file } or nil
  local out = {}
  for _, raw in ipairs(rg_vimgrep([[#\[utoipa::path\(]], nil, paths)) do
    local m = parse_vimgrep(raw)
    if m then
      local lines = vim.fn.readfile(m.file, '', m.lnum + 40)
      local method, rel
      for i = m.lnum, math.min(#lines, m.lnum + 40) do
        local l = lines[i]
        if not method then
          method = l:match('^%s*(get)%s*,') or l:match('^%s*(post)%s*,')
              or l:match('^%s*(put)%s*,') or l:match('^%s*(delete)%s*,')
              or l:match('^%s*(patch)%s*,') or l:match('^%s*(head)%s*,')
              or l:match('^%s*(options)%s*,') or l:match('^%s*(trace)%s*,')
        end
        if not rel then rel = l:match('path%s*=%s*"([^"]+)"') end
        if method and rel then break end
        if l:match('^%s*%)%s*%]') then break end
      end
      if method and rel then
        local handler, hlnum, doc = find_handler_after(m.file, m.lnum, 120)
        table.insert(out, {
          method       = method:upper(),
          path         = rel,
          file         = m.file,
          attr_lnum    = m.lnum,
          handler      = handler,
          handler_lnum = hlnum,
          doc          = doc,
          kind         = 'no-prefix',
        })
      end
    end
  end
  return out
end

local function collect_all(file)
  local anchored          = collect_anchored(file)
  local utoipa            = collect_utoipa(file)

  -- Index utoipa entries by handler position so we can cross-check anchors.
  local utoipa_by_handler = {}
  for _, e in ipairs(utoipa) do
    if e.handler_lnum then
      utoipa_by_handler[e.file .. ':' .. e.handler_lnum] = e
    end
  end

  local seen = {}
  for _, e in ipairs(anchored) do
    if e.handler_lnum then
      seen[e.file .. ':' .. e.handler_lnum] = true
      local u = utoipa_by_handler[e.file .. ':' .. e.handler_lnum]
      if u then
        if u.method ~= e.method then e.mismatch_method = u.method end
        -- `path = "/"` is the router-root case; anchor's full URL ends with the parent prefix.
        if u.path ~= '/' and e.path:sub(- #u.path) ~= u.path then
          e.mismatch_path = u.path
        end
      end
    end
  end

  local items = {}
  for _, e in ipairs(anchored) do table.insert(items, e) end
  for _, e in ipairs(utoipa) do
    local key = e.handler_lnum and (e.file .. ':' .. e.handler_lnum)
    if not (key and seen[key]) then table.insert(items, e) end
  end

  table.sort(items, function(a, b)
    if a.path ~= b.path then return a.path < b.path end
    return a.method < b.method
  end)
  return items
end
M.collect = collect_all

local function relpath(filename)
  local cwd = vim.fn.getcwd()
  if filename:sub(1, #cwd + 1) == cwd .. '/' then
    return filename:sub(#cwd + 2)
  end
  return vim.fn.fnamemodify(filename, ':~')
end

-- Swagger-style per-method colors pulled from the theme palette.
local palette = require('config.theme_colors')
local method_colors = {
  GET     = palette.blue,
  POST    = palette.green,
  PUT     = palette.orange,
  PATCH   = palette.emerald,
  DELETE  = palette.red,
  HEAD    = palette.purple,
  OPTIONS = palette.cyan,
  TRACE   = palette.silver,
}
local METHOD_HL = {}
local function set_method_hl()
  for method, color in pairs(method_colors) do
    local group = 'AxumMethod' .. method
    vim.api.nvim_set_hl(0, group, { fg = color, bold = true })
    METHOD_HL[method] = group
  end
end
set_method_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_method_hl })

-- '…' on partial paths means "prefix unknown" - dim so the match-highlight stays readable.
local PARTIAL_MARK = '…'
local DOC_MAX = 60

local function trunc(s, n)
  if vim.api.nvim_strwidth(s) <= n then return s end
  return s:sub(1, n - 1) .. '…'
end

local function make_entry(item)
  local method   = string.format('%-7s', item.method)
  local mark     = item.kind == 'no-prefix' and PARTIAL_MARK or ''
  -- Dim '/api/v<N>/' prefix, '{...}' placeholders, and '?...' query so literal
  -- route segments stand out.
  local q        = item.path:find('?', 1, true)
  local base     = q and item.path:sub(1, q - 1) or item.path
  local path_q   = q and item.path:sub(q) or ''
  local pre_end  = base:match('^/api/v%d+()/')
  local path_pre = pre_end and base:sub(1, pre_end - 1) or ''
  local path_b   = pre_end and base:sub(pre_end) or base
  local arrow    = item.handler and ' -> ' or ''
  local handler  = item.handler or ''
  local doc      = item.doc and ('  ' .. trunc(item.doc, DOC_MAX)) or ''
  local file_tag = '  ' .. relpath(item.file)
  local text     = method .. mark .. path_pre .. path_b .. path_q
      .. arrow .. handler .. doc .. file_tag

  local p0       = 0
  local p1       = #method
  local p2       = p1 + #mark
  local p3       = p2 + #path_pre
  local p4       = p3 + #path_b
  local p5       = p4 + #path_q
  local p6       = p5 + #arrow
  local p7       = p6 + #handler
  local p8       = p7 + #doc
  local p9       = p8 + #file_tag

  -- Highlight literals bright and {placeholders} dim within path_b.
  local path_hls = {}
  local i        = 1
  while i <= #path_b do
    local lb, rb = path_b:find('{[^}]-}', i)
    if not lb then
      table.insert(path_hls, { { p3 + i - 1, p4 }, 'TelescopeResultsIdentifier' })
      break
    end
    if lb > i then
      table.insert(path_hls, { { p3 + i - 1, p3 + lb - 1 }, 'TelescopeResultsIdentifier' })
    end
    table.insert(path_hls, { { p3 + lb - 1, p3 + rb }, 'TelescopeResultsComment' })
    i = rb + 1
  end

  return {
    value    = item,
    ordinal  = item.method .. ' ' .. item.path .. ' ' .. handler .. ' ' .. (item.doc or ''),
    filename = item.file,
    lnum     = item.handler_lnum or item.anchor_lnum or item.attr_lnum or 1,
    col      = 1,
    display  = function()
      local hls = {}
      local function add(a, b, hl) if a < b then table.insert(hls, { { a, b }, hl }) end end
      add(p0, p1, METHOD_HL[item.method] or 'TelescopeResultsNormal')
      add(p1, p2, 'TelescopeResultsComment')
      add(p2, p3, 'TelescopeResultsComment')
      for _, h in ipairs(path_hls) do
        if h[1][1] < h[1][2] then table.insert(hls, h) end
      end
      add(p4, p5, 'TelescopeResultsComment')
      add(p5, p6, 'Operator')
      add(p6, p7, 'Function')
      add(p7, p8, 'TelescopeResultsComment')
      add(p8, p9, 'TelescopeResultsFileName')
      return text, hls
    end,
  }
end

function M.open(opts)
  opts = opts or {}
  local file = opts.file
  local items = collect_all(file)
  if #items == 0 then
    vim.notify(file and 'No endpoints in this file' or 'No axum/utoipa endpoints found',
      vim.log.levels.INFO)
    return
  end

  -- Diagonal trackpad scroll leaks horizontal motion (zh/zl) and jitters the list.
  -- hor:1 keeps horizontal scroll available but with the smallest possible step.
  local saved_mousescroll = vim.o.mousescroll
  vim.o.mousescroll = 'ver:3,hor:1'

  pickers.new({}, {
    prompt_title    = file and 'Axum endpoints (file)' or 'Axum endpoints',
    finder          = finders.new_table({ results = items, entry_maker = make_entry }),
    sorter          = conf.generic_sorter({}),
    previewer       = conf.grep_previewer({}),
    attach_mappings = function(prompt_bufnr, _)
      vim.api.nvim_create_autocmd('BufWipeout', {
        buffer   = prompt_bufnr,
        once     = true,
        callback = function() vim.o.mousescroll = saved_mousescroll end,
      })
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not sel or not sel.value then return end
        vim.cmd('edit ' .. vim.fn.fnameescape(sel.value.file))
        vim.api.nvim_win_set_cursor(0, { sel.lnum, 0 })
        vim.cmd('normal! zz')
      end)
      return true
    end,
  }):find()
end

vim.api.nvim_create_user_command('AxumRoutes', function() M.open() end,
  { desc = 'List axum/utoipa endpoints in Telescope' })

vim.api.nvim_create_user_command('AxumRoutesFile',
  function() M.open({ file = vim.api.nvim_buf_get_name(0) }) end,
  { desc = 'List axum/utoipa endpoints in the current file' })

return M
