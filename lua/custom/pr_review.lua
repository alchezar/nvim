-- Local PR review of a checked-out PR branch. Comments live in memory and ride
-- extmarks; <leader>gV comments a selection, <leader>gRs opens the summary.

local theme = require('config.theme_colors')

local M = {}
local ns = vim.api.nvim_create_namespace('user_pr_review')
local ui_ns = vim.api.nvim_create_namespace('user_pr_review_ui')

-- list of { path, start_line, end_line, side='RIGHT', body, bufnr, extmark_id }
M.comments = {}
-- Review body, kept across window closes until a review goes out.
M.summary = ''

local SIGN = vim.fn.nr2char(0xF075) -- speech-bubble glyph
vim.api.nvim_set_hl(0, 'PRReviewComment', { fg = theme.cyan })
vim.api.nvim_set_hl(0, 'PRReviewLocation', { fg = theme.blue, bold = true })
vim.api.nvim_set_hl(0, 'PRReviewSummary', { fg = theme.purple, bold = true })
vim.api.nvim_set_hl(0, 'PRReviewCurrent', { fg = theme.yellow })

-- No `event` leaves the review pending on GitHub.
local VERDICTS = {
  { label = 'Comment',                         event = 'COMMENT' },
  { label = 'Request changes',                 event = 'REQUEST_CHANGES' },
  { label = 'Approve',                         event = 'APPROVE' },
  { label = 'Pending draft (finish on GitHub)' },
}

-- git helpers (same shape as branch_review; module is self-contained) --------

local function git(args)
  local out = vim.fn.systemlist(vim.list_extend({ 'git' }, args))
  if vim.v.shell_error ~= 0 then return nil end
  return out
end

local function repo_root()
  local out = git({ 'rev-parse', '--show-toplevel' })
  return out and out[1] ~= '' and out[1] or nil
end

local function head_sha()
  local out = git({ 'rev-parse', 'HEAD' })
  return out and out[1] or nil
end

-- Relative POSIX path of a buffer from the repo root, nil if outside / unnamed.
local function rel_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return nil end
  local root = repo_root()
  if not root then return nil end
  local abs = vim.fn.fnamemodify(name, ':p')
  if abs:sub(1, #root + 1) ~= root .. '/' then return nil end
  return abs:sub(#root + 2)
end

-- extmarks --------------------------------------------------------------------

local function set_mark(buf, s, e)
  return vim.api.nvim_buf_set_extmark(buf, ns, s - 1, 0, {
    sign_text = SIGN,
    sign_hl_group = 'PRReviewComment',
    end_row = e - 1,
    -- Both ends sit at column 0; a line opened above the last one must push
    -- the end down with it, or the comment slips onto the new line.
    end_right_gravity = true,
    priority = 200,
  })
end

-- Live line range from the extmark (survives edits); fall back to stored lines.
local function live_range(rec)
  if rec.extmark_id and vim.api.nvim_buf_is_valid(rec.bufnr) then
    local p = vim.api.nvim_buf_get_extmark_by_id(rec.bufnr, ns, rec.extmark_id, { details = true })
    if p[1] then
      local s = p[1] + 1
      local e = (p[3] and p[3].end_row and p[3].end_row + 1) or s
      return s, e
    end
  end
  return rec.start_line, rec.end_line
end

local function drop_mark(rec)
  if rec.extmark_id and vim.api.nvim_buf_is_valid(rec.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, rec.bufnr, ns, rec.extmark_id)
  end
end

local function clear_marks()
  for _, rec in ipairs(M.comments) do drop_mark(rec) end
end

-- One comment object for the reviews API: single line uses line+side; a range
-- adds start_line+start_side (GitHub requires start_line < line).
local function comment_for_api(rec)
  local s, e = live_range(rec)
  local c = { path = rec.path, line = e, side = 'RIGHT', body = rec.body }
  if e > s then
    c.start_line = s
    c.start_side = 'RIGHT'
  end
  return c
end

local function location(rec)
  local s, e = live_range(rec)
  return e > s and ('%s:%d-%d'):format(rec.path, s, e) or ('%s:%d'):format(rec.path, s)
end

-- The commented lines as they are now. A closed buffer is read from disk.
local function code_lines(rec)
  local s, e = live_range(rec)
  if vim.api.nvim_buf_is_valid(rec.bufnr) and vim.api.nvim_buf_is_loaded(rec.bufnr) then
    return vim.api.nvim_buf_get_lines(rec.bufnr, s - 1, e, false)
  end
  local ok, lines = pcall(vim.fn.readfile, (repo_root() or '.') .. '/' .. rec.path)
  return ok and vim.list_slice(lines, s, e) or {}
end

-- GitHub helpers (async; callbacks are schedule-wrapped for UI safety) -------

-- Resolve owner/name/number of the current branch's PR from its URL.
local function current_pr(cb)
  vim.system({ 'gh', 'pr', 'view', '--json', 'url', '--jq', '.url' }, { text = true },
    vim.schedule_wrap(function(r)
      if r.code ~= 0 then return cb(nil) end
      local owner, name, num = vim.trim(r.stdout):match('([^/]+)/([^/]+)/pull/(%d+)')
      if not owner then return cb(nil) end
      cb({ owner = owner, name = name, number = tonumber(num) })
    end))
end

-- Does the viewer already have an unsubmitted (PENDING) review on this PR?
-- Unsure means false, since GitHub's atomic POST refuses a second draft anyway.
local function has_pending(pr, cb)
  local query = [[
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      reviews(first:50,states:[PENDING]){ nodes { viewerDidAuthor } }
    }
  }
}]]
  vim.system({
    'gh', 'api', 'graphql',
    '-f', 'query=' .. query,
    '-f', 'owner=' .. pr.owner,
    '-f', 'name=' .. pr.name,
    '-F', 'number=' .. pr.number,
  }, { text = true }, vim.schedule_wrap(function(r)
    if r.code ~= 0 then return cb(false) end
    local ok, data = pcall(vim.json.decode, r.stdout)
    if not ok then return cb(false) end
    local nodes = vim.tbl_get(data, 'data', 'repository', 'pullRequest', 'reviews', 'nodes') or {}
    for _, n in ipairs(nodes) do
      if n.viewerDidAuthor then return cb(true) end
    end
    cb(false)
  end))
end

-- POST one review. On success the store is cleared; a failure keeps it, so an
-- off-diff comment (GitHub rejects the whole review with 422) can be fixed.
local function post_review(pr, payload, label, on_done)
  local tmp = vim.fn.tempname()
  local f = io.open(tmp, 'w')
  if not f then
    vim.notify('PR review: cannot write temp file', vim.log.levels.ERROR)
    return
  end
  f:write(vim.json.encode(payload))
  f:close()
  vim.system({
    'gh', 'api',
    ('repos/%s/%s/pulls/%d/reviews'):format(pr.owner, pr.name, pr.number),
    '--method', 'POST', '--input', tmp,
  }, { text = true }, vim.schedule_wrap(function(r)
    os.remove(tmp)
    if r.code ~= 0 then
      vim.notify('PR review push failed: ' .. vim.trim(r.stderr), vim.log.levels.ERROR)
      return
    end
    clear_marks()
    M.comments = {}
    M.summary = ''
    if on_done then on_done() end
    vim.notify('PR review: ' .. label, vim.log.levels.INFO)
  end))
end

-- Sends the store as one review. Without a verdict it is the pending draft.
function M.push(verdict, on_done)
  verdict = verdict or VERDICTS[#VERDICTS]
  if vim.fn.executable('gh') == 0 then
    vim.notify('PR review: gh CLI not found', vim.log.levels.ERROR)
    return
  end
  local body = vim.trim(M.summary)
  if #M.comments == 0 and body == '' and verdict.event ~= 'APPROVE' then
    vim.notify('PR review: no comments to push', vim.log.levels.INFO)
    return
  end
  local commit_id = head_sha()
  if not commit_id then
    vim.notify('PR review: not a git repository', vim.log.levels.ERROR)
    return
  end
  current_pr(function(pr)
    if not pr then
      vim.notify('PR review: no PR for the current branch', vim.log.levels.WARN)
      return
    end
    has_pending(pr, function(pending)
      if pending then
        vim.notify('PR review: a pending draft already exists - submit it in snacks first', vim.log.levels.WARN)
        return
      end
      local payload = { commit_id = commit_id, event = verdict.event }
      if body ~= '' then payload.body = body end
      -- An empty Lua table would encode as `{}`, so the key is left out.
      if #M.comments > 0 then
        payload.comments = vim.tbl_map(comment_for_api, M.comments)
      end
      local label = verdict.event and ('submitted as ' .. verdict.label:lower())
          or 'draft pushed - view & submit in snacks (gh_pr)'
      post_review(pr, payload, label, on_done)
    end)
  end)
end

-- review window ---------------------------------------------------------------

-- Drafts on the left, the commented code over the editor on the right.
-- `cur` is what the editor holds: { rec, new } or { summary = true }.
local ui = { wins = {}, bufs = {}, cur = {}, rows = {} }

local function is_open()
  return ui.wins.edit ~= nil and vim.api.nvim_win_is_valid(ui.wins.edit)
end

local FOOTERS = {
  list = ' <CR> edit | dd delete | q close ',
  ctx = ' <Tab> editor | q close ',
  edit = ' :wq save | :q close | <C-g> suggestion | <C-s> submit | <Tab> drafts ',
}

-- Geometry of the three floats inside one 90% box, like the lazygit float.
local function layout(ctx_lines)
  local editor_h = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  local height = math.max(8, math.floor(editor_h * 0.9))
  local width = math.max(30, math.floor(vim.o.columns * 0.9))
  local row = math.max(0, math.floor((editor_h - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  local list_w = math.max(10, math.floor(width * 0.35) - 2)
  local right = { col = col + list_w + 2, width = math.max(10, width - list_w - 4) }
  local ctx_h = math.max(1, math.min(ctx_lines, math.floor(height * 0.4)))
  return {
    list = { row = row, col = col, width = list_w, height = height - 2 },
    ctx = { row = row, col = right.col, width = right.width, height = ctx_h },
    edit = { row = row + ctx_h + 2, col = right.col, width = right.width, height = math.max(1, height - ctx_h - 4) },
  }
end

local function win_config(name, geometry, title)
  return vim.tbl_extend('force', geometry, {
    relative = 'editor',
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    footer = FOOTERS[name],
    footer_pos = 'center',
  })
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function editor_text()
  return vim.trim(table.concat(vim.api.nvim_buf_get_lines(ui.bufs.edit, 0, -1, false), '\n'))
end

local function render_list()
  local lines, marks, rows = {}, {}, {}
  local function block(entry, title, hl, body)
    local current = (entry.rec ~= nil and entry.rec == ui.cur.rec) or (entry.summary and ui.cur.summary)
    lines[#lines + 1] = (current and '> ' or '  ') .. title
    marks[#marks + 1] = { #lines - 1, hl, current, #lines[#lines] }
    for _, l in ipairs(body ~= '' and vim.split(body, '\n') or {}) do
      lines[#lines + 1] = '    ' .. l
    end
    lines[#lines + 1] = ''
    for r = #rows + 1, #lines do rows[r] = entry end
  end
  for _, rec in ipairs(M.comments) do
    block({ rec = rec }, location(rec), 'PRReviewLocation', rec.body)
  end
  if ui.cur.new then
    block(ui.cur, location(ui.cur.rec) .. '  (new)', 'PRReviewLocation', '')
  end
  local total = ('Review summary (%d comment%s)'):format(#M.comments, #M.comments == 1 and '' or 's')
  block({ summary = true }, total, 'PRReviewSummary', M.summary)
  lines[#lines] = nil
  ui.rows = rows
  set_lines(ui.bufs.list, lines)
  vim.api.nvim_buf_clear_namespace(ui.bufs.list, ui_ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(ui.bufs.list, ui_ns, m[1], 2, { end_col = m[4], hl_group = m[2] })
    if m[3] then
      vim.api.nvim_buf_set_extmark(ui.bufs.list, ui_ns, m[1], 0, { end_col = 1, hl_group = 'PRReviewCurrent' })
      vim.api.nvim_win_set_cursor(ui.wins.list, { m[1] + 1, 0 })
    end
  end
end

-- Writes the editor into what it holds. An empty comment is never stored.
local function save()
  local text = editor_text()
  local cur = ui.cur
  if cur.summary then
    M.summary = text
  elseif text ~= '' then
    cur.rec.body = text
    if cur.new then
      cur.rec.extmark_id = set_mark(cur.rec.bufnr, cur.rec.start_line, cur.rec.end_line)
      table.insert(M.comments, cur.rec)
      cur.new = nil
      vim.notify(('Review comment added (%d total)'):format(#M.comments), vim.log.levels.INFO)
    end
  end
  vim.bo[ui.bufs.edit].modified = false
  render_list()
end

-- What goes out with the summary, shown in place of the code.
local function summary_lines()
  local counts, files = {}, {}
  for _, rec in ipairs(M.comments) do
    if not counts[rec.path] then files[#files + 1] = rec.path end
    counts[rec.path] = (counts[rec.path] or 0) + 1
  end
  local lines = { ('%d comment%s in %d file%s'):format(#M.comments, #M.comments == 1 and '' or 's',
    #files, #files == 1 and '' or 's') }
  for _, path in ipairs(files) do lines[#lines + 1] = ('  %d  %s'):format(counts[path], path) end
  return lines
end

local function set_title(name, title)
  vim.api.nvim_win_set_config(ui.wins[name], { title = ' ' .. title .. ' ' })
end

-- Loads an entry into the right side and moves the editor onto it.
local function show(cur)
  ui.cur = cur
  local code = cur.summary and summary_lines() or code_lines(cur.rec)
  set_lines(ui.bufs.ctx, code)
  -- Highlighted by parser, so no FileType autocmd fires on a scratch buffer.
  pcall(vim.treesitter.stop, ui.bufs.ctx)
  local ft = ''
  if not cur.summary then
    local src = cur.rec.bufnr
    ft = vim.api.nvim_buf_is_valid(src) and vim.bo[src].filetype
        or vim.filetype.match({ filename = cur.rec.path }) or ''
  end
  local parsed = ft ~= '' and pcall(vim.treesitter.start, ui.bufs.ctx, vim.treesitter.language.get_lang(ft) or ft)
  vim.bo[ui.bufs.ctx].syntax = parsed and '' or ft

  -- The loaded text is the editor's start, not an edit to undo.
  local levels = vim.bo[ui.bufs.edit].undolevels
  vim.bo[ui.bufs.edit].undolevels = -1
  vim.api.nvim_buf_set_lines(ui.bufs.edit, 0, -1, false,
    vim.split(cur.summary and M.summary or cur.rec.body or '', '\n'))
  vim.bo[ui.bufs.edit].undolevels = levels
  vim.bo[ui.bufs.edit].modified = false

  local geometry = layout(#code)
  for name, win in pairs(ui.wins) do
    vim.api.nvim_win_set_config(win, vim.tbl_extend('force', geometry[name], { relative = 'editor' }))
  end
  set_title('ctx', cur.summary and (ui.pr or 'Review') or location(cur.rec))
  set_title('edit', cur.summary and 'Review summary' or 'Comment')
  render_list()

  vim.api.nvim_set_current_win(ui.wins.edit)
  vim.api.nvim_win_set_cursor(ui.wins.edit, { vim.api.nvim_buf_line_count(ui.bufs.edit), 0 })
  if editor_text() == '' then vim.cmd('startinsert') else vim.cmd('stopinsert') end

  if cur.summary and not ui.pr and vim.fn.executable('gh') == 1 then
    current_pr(function(pr)
      if not is_open() then return end
      ui.pr = pr and ('%s/%s#%d'):format(pr.owner, pr.name, pr.number) or 'no PR for this branch'
      if ui.cur.summary then set_title('ctx', ui.pr) end
    end)
  end
end

local function close()
  -- A review may land after the window is gone.
  if ui.closing or not ui.origin then return end
  ui.closing = true
  pcall(vim.api.nvim_del_augroup_by_name, 'PRReviewWindow')
  vim.cmd('stopinsert')
  -- Focus leaves first, or closing the focused float lands on a random window.
  if ui.origin and vim.api.nvim_win_is_valid(ui.origin) then
    pcall(vim.api.nvim_set_current_win, ui.origin)
  end
  for _, win in pairs(ui.wins) do
    if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  end
  ui = { wins = {}, bufs = {}, cur = {}, rows = {} }
end

-- Moves the editor to another entry; typed text is saved, never dropped.
local function switch(cur)
  save()
  show(cur)
end

local function entry_at_cursor()
  return ui.rows[vim.api.nvim_win_get_cursor(ui.wins.list)[1]]
end

local function edit_entry()
  local entry = entry_at_cursor()
  if not entry then return end
  local same = (entry.summary and ui.cur.summary) or (entry.rec ~= nil and entry.rec == ui.cur.rec)
  if same then return vim.api.nvim_set_current_win(ui.wins.edit) end
  switch(entry)
end

local function delete_entry()
  local entry = entry_at_cursor()
  if not entry then return end
  local row = vim.api.nvim_win_get_cursor(ui.wins.list)[1]
  local loaded = (entry.summary and ui.cur.summary) or (entry.rec ~= nil and entry.rec == ui.cur.rec)
  if entry.summary then
    M.summary = ''
  else
    drop_mark(entry.rec)
    M.comments = vim.tbl_filter(function(rec) return rec ~= entry.rec end, M.comments)
  end
  if loaded then
    show({ summary = true })
    vim.api.nvim_set_current_win(ui.wins.list)
    vim.cmd('stopinsert')
  else
    render_list()
  end
  local last = vim.api.nvim_buf_line_count(ui.bufs.list)
  vim.api.nvim_win_set_cursor(ui.wins.list, { math.min(row, last), 0 })
end

-- A suggestion block holding the commented code, ready to be rewritten. The
-- fence outgrows any backtick run inside the code.
local function suggest()
  if ui.cur.summary then return end
  local code = code_lines(ui.cur.rec)
  local fence = '```'
  for _, line in ipairs(code) do
    for run in line:gmatch('`+') do
      if #run >= #fence then fence = ('`'):rep(#run + 1) end
    end
  end
  local block = { fence .. 'suggestion' }
  vim.list_extend(block, code)
  block[#block + 1] = fence
  local row = vim.api.nvim_win_get_cursor(ui.wins.edit)[1]
  -- An empty cursor line is replaced, else the block goes below it.
  local blank = vim.api.nvim_buf_get_lines(ui.bufs.edit, row - 1, row, false)[1] == ''
  local at = blank and row - 1 or row
  vim.api.nvim_buf_set_lines(ui.bufs.edit, at, blank and row or at, false, block)
  vim.api.nvim_win_set_cursor(ui.wins.edit, { at + 2, 0 })
end

-- First press moves to the summary, the next one asks for a verdict and sends.
local function submit()
  if not ui.cur.summary then return switch({ summary = true }) end
  save()
  vim.cmd('stopinsert')
  vim.ui.select(VERDICTS, {
    prompt = 'Submit review as',
    format_item = function(item) return item.label end,
  }, function(verdict)
    if verdict then M.push(verdict, close) end
  end)
end

local function open_window(cur)
  ui = { wins = {}, bufs = {}, cur = {}, rows = {}, origin = vim.api.nvim_get_current_win() }
  local geometry = layout(1)
  for _, name in ipairs({ 'list', 'ctx', 'edit' }) do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    ui.bufs[name] = buf
    ui.wins[name] = vim.api.nvim_open_win(buf, false, win_config(name, geometry[name], name))
    vim.w[ui.wins[name]].pr_review = name
    vim.wo[ui.wins[name]].wrap = name ~= 'ctx'
    vim.wo[ui.wins[name]].linebreak = true
  end
  vim.wo[ui.wins.list].cursorline = true
  vim.wo[ui.wins.list].breakindent = true
  set_title('list', 'Drafts')

  local edit = ui.bufs.edit
  vim.bo[edit].filetype = 'markdown'
  vim.bo[edit].buftype = 'acwrite'
  pcall(vim.api.nvim_buf_set_name, edit, 'pr-review/' .. edit)

  local group = vim.api.nvim_create_augroup('PRReviewWindow', { clear = true })
  vim.api.nvim_create_autocmd('BufWriteCmd', { group = group, buffer = edit, callback = save })
  -- Drop the modified flag right before any quit so :q never trips E37.
  vim.api.nvim_create_autocmd('QuitPre', {
    group = group,
    buffer = edit,
    callback = function() vim.bo[edit].modified = false end,
  })
  -- The three floats are one window, so closing any of them closes all.
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    pattern = vim.tbl_map(tostring, vim.tbl_values(ui.wins)),
    callback = close,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      local resized = layout(vim.api.nvim_buf_line_count(ui.bufs.ctx))
      for name, win in pairs(ui.wins) do
        vim.api.nvim_win_set_config(win, vim.tbl_extend('force', resized[name], { relative = 'editor' }))
      end
    end,
  })

  local function map(name, modes, lhs, rhs)
    vim.keymap.set(modes, lhs, rhs, { buffer = ui.bufs[name], nowait = true, silent = true })
  end
  for _, name in ipairs({ 'list', 'ctx' }) do
    map(name, 'n', 'q', close)
    map(name, 'n', '<Esc>', close)
    map(name, 'n', '<Tab>', function() vim.api.nvim_set_current_win(ui.wins.edit) end)
  end
  map('list', 'n', '<CR>', edit_entry)
  map('list', 'n', 'dd', delete_entry)
  map('list', 'n', '<C-s>', submit)
  map('edit', 'n', '<Tab>', function() vim.api.nvim_set_current_win(ui.wins.list) end)
  map('edit', { 'n', 'i' }, '<C-s>', submit)
  map('edit', { 'n', 'i' }, '<C-g>', suggest)

  show(cur)
end

-- public ----------------------------------------------------------------------

-- opts comes from the user command (range); a keymap call passes nothing.
function M.add_comment(opts)
  if is_open() then return end
  local buf = vim.api.nvim_get_current_buf()
  local path = rel_path(buf)
  if not path then
    vim.notify('PR review: not a file inside the repo', vim.log.levels.WARN)
    return
  end
  local s, e
  if opts and opts.range and opts.range > 0 then
    s, e = opts.line1, opts.line2
  elseif vim.fn.mode():match('[vV\22]') then
    vim.cmd('normal! \27') -- leave visual so '< / '> update
    s, e = vim.fn.line("'<"), vim.fn.line("'>")
  else
    s = vim.fn.line('.')
    e = s
  end
  if s > e then s, e = e, s end
  -- Only head-version lines (RIGHT) can be commented; deleted lines are out.
  local rec = { path = path, start_line = s, end_line = e, side = 'RIGHT', body = '', bufnr = buf }
  open_window({ rec = rec, new = true })
end

-- Opens the window on the review summary, the step before sending.
function M.review()
  if is_open() then return end
  open_window({ summary = true })
end

function M.clear()
  close()
  clear_marks()
  M.comments = {}
  vim.notify('PR review: comments cleared', vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('PRReviewComment', M.add_comment,
  { range = true, desc = 'PR review: add comment on line/selection' })
vim.api.nvim_create_user_command('PRReviewSubmit', M.review,
  { desc = 'PR review: open the drafts and submit the review' })
vim.api.nvim_create_user_command('PRReviewClear', M.clear,
  { desc = 'PR review: discard all pending comments' })

return M
