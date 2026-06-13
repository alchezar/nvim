-- Local PR review: collect inline comments while reading a checked-out PR branch,
-- then push them as one pending review via `gh`. Comments live only in memory and
-- ride extmarks so they follow edits in-session. Pairs with snacks (picker), which
-- shows the draft (gh_diff) and submits it (gh_submit_review).
--   <leader>gRc  add a comment on the current line / visual selection (RIGHT side)
--   <leader>gRs  push all comments as a pending draft review on GitHub
-- Only head-version lines (RIGHT) can be commented; deleted (LEFT) lines are out of scope.
-- GitHub accepts a comment only on a line that is part of the PR diff; an off-diff
-- comment makes the whole push 422 (atomic) - the store is kept so you can fix & retry.
-- If a pending draft already exists, push aborts so it never overwrites unsubmitted work.

local theme = require('config.theme_colors')

local M = {}
local ns = vim.api.nvim_create_namespace('user_pr_review')

-- list of { path, start_line, end_line, side='RIGHT', body, bufnr, extmark_id }
M.comments = {}

local SIGN = vim.fn.nr2char(0xF075) -- speech-bubble glyph
vim.api.nvim_set_hl(0, 'PRReviewComment', { fg = theme.cyan })

-- git helpers (same shape as branch_review; module is self-contained) ----------

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

-- Relative POSIX path of a buffer from the repo root, or nil if outside / unnamed.
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
    priority = 200,
  })
end

-- Live line range from the extmark (survives edits); fall back to stored lines.
local function live_range(rec)
  if vim.api.nvim_buf_is_valid(rec.bufnr) then
    local p = vim.api.nvim_buf_get_extmark_by_id(rec.bufnr, ns, rec.extmark_id, { details = true })
    if p[1] then
      local s = p[1] + 1
      local e = (p[3] and p[3].end_row and p[3].end_row + 1) or s
      return s, e
    end
  end
  return rec.start_line, rec.end_line
end

local function clear_marks()
  for _, rec in ipairs(M.comments) do
    if vim.api.nvim_buf_is_valid(rec.bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, rec.bufnr, ns, rec.extmark_id)
    end
  end
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

-- floating editor -------------------------------------------------------------

-- Compact scratch float at the cursor with full vim modes/motions.
-- :w (or :wq) saves the comment, :q quits without saving.
local function open_editor(title, on_submit)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, buf, 'pr-review/' .. buf)
  vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    width = 50,
    height = 6,
    row = 1,
    col = 0,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    footer = ' :wq save | :q cancel ',
    footer_pos = 'center',
  })

  local staged -- text captured by :w; stays nil on a plain :q (cancel)
  -- Drop the modified flag right before any quit so :q never trips E37.
  vim.api.nvim_create_autocmd('QuitPre', {
    buffer = buf,
    callback = function() vim.bo[buf].modified = false end,
  })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      staged = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
      vim.bo[buf].modified = false
    end,
  })
  -- Apply only when the window closes after a :w; a plain :q leaves staged nil.
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if staged and staged ~= '' then on_submit(staged) end
    end,
  })
  vim.cmd('startinsert')
end

-- GitHub helpers (async; callbacks are schedule-wrapped for UI safety) ---------

-- Resolve owner/name/number of the current branch's PR from its URL (one call).
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
-- On any uncertainty returns false: GitHub's atomic POST still refuses a second draft.
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

-- POST the comments as a pending review (no `event` field). On success clear the
-- store; on failure keep it so the user can fix an off-diff comment and retry.
local function create_pending(pr, commit_id, comments)
  local tmp = vim.fn.tempname()
  local f = io.open(tmp, 'w')
  if not f then
    vim.notify('PR review: cannot write temp file', vim.log.levels.ERROR)
    return
  end
  f:write(vim.json.encode({ commit_id = commit_id, comments = comments }))
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
    vim.notify('PR review: draft pushed - view & submit in snacks (gh_pr)', vim.log.levels.INFO)
  end))
end

-- public ----------------------------------------------------------------------

-- opts comes from the user command (range); a keymap call passes nothing.
function M.add_comment(opts)
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
  open_editor(('%s:%d'):format(path, s), function(body)
    if body == '' then return end
    local id = set_mark(buf, s, e)
    table.insert(M.comments, {
      path = path, start_line = s, end_line = e, side = 'RIGHT',
      body = body, bufnr = buf, extmark_id = id,
    })
    vim.notify(('Review comment added (%d total)'):format(#M.comments), vim.log.levels.INFO)
  end)
end

function M.push()
  if vim.fn.executable('gh') == 0 then
    vim.notify('PR review: gh CLI not found', vim.log.levels.ERROR)
    return
  end
  if #M.comments == 0 then
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
      local comments = {}
      for _, rec in ipairs(M.comments) do
        comments[#comments + 1] = comment_for_api(rec)
      end
      create_pending(pr, commit_id, comments)
    end)
  end)
end

function M.clear()
  clear_marks()
  M.comments = {}
  vim.notify('PR review: comments cleared', vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('PRReviewComment', M.add_comment,
  { range = true, desc = 'PR review: add comment on line/selection' })
vim.api.nvim_create_user_command('PRReviewSubmit', M.push,
  { desc = 'PR review: push comments as a pending draft' })
vim.api.nvim_create_user_command('PRReviewClear', M.clear,
  { desc = 'PR review: discard all pending comments' })

return M
