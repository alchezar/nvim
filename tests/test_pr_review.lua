-- Local PR review from custom/pr_review.lua. Comments typed in the review
-- window ride extmarks and go out as one review through a fake `gh` on PATH,
-- which logs its runs and keeps the posted review.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local bin

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      bin = vim.fn.tempname()
      vim.fn.mkdir(bin, 'p')
      vim.fn.writefile({
        '#!/bin/sh',
        'd=$(dirname "$0")',
        'echo "$*" >> "$d/log"',
        'case "$1 $2" in',
        '"pr view") echo https://github.com/acme/app/pull/7 ;;',
        '"api graphql") cat "$d/reviews" ;;',
        '"api repos/acme/app/pulls/7/reviews")',
        '  [ -f "$d/fail" ] && { echo "HTTP 422" >&2; exit 1; }',
        '  while [ $# -gt 0 ]; do [ "$1" = --input ] && cp "$2" "$d/posted"; shift; done',
        '  echo "{}" ;;',
        'esac',
      }, bin .. '/gh')
      vim.fn.setfperm(bin .. '/gh', 'rwxr-xr-x')
      local nodes = { data = { repository = { pullRequest = { reviews = { nodes = {} } } } } }
      vim.fn.writefile({ vim.json.encode(nodes) }, bin .. '/reviews')
      child.lua([[
        vim.env.PATH = ... .. ':' .. vim.env.PATH
        _G.notes = {}
        vim.notify = function(msg) table.insert(_G.notes, msg) end
      ]], { bin })
    end,
    post_once = child.stop,
  },
})

-- A git repo holding `src/a.rs`, opened in the child; returns the HEAD sha.
local function open_repo(dir)
  vim.fn.mkdir(dir .. '/src', 'p')
  vim.fn.writefile({ 'one', 'two', 'three', 'four' }, dir .. '/src/a.rs')
  for _, args in ipairs({ { 'init', '-q' }, { 'add', '.' }, { 'commit', '-q', '-m', 'c' } }) do
    local res = vim.system(vim.list_extend({ 'git', '-c', 'user.name=t', '-c', 'user.email=t@t' }, args), {
      cwd = dir,
      env = { GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
    }):wait()
    assert(res.code == 0, res.stderr)
  end
  child.lua([[
    local dir = ...
    vim.cmd.cd(dir)
    vim.cmd.edit(dir .. '/src/a.rs')
    require('custom.pr_review')
  ]], { dir })
  return vim.trim(vim.system({ 'git', 'rev-parse', 'HEAD' }, { cwd = dir }):wait().stdout)
end

local function new_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return vim.uv.fs_realpath(dir)
end

-- Types `body` into the float `range` opens, then leaves it with `quit`.
local function comment(range, body, quit)
  child.cmd(range .. 'PRReviewComment')
  child.type_keys(body, '<Esc>', ':' .. (quit or 'wq') .. '<CR>')
end

-- Comments in the store as `path:start-end body`.
local function stored()
  return child.lua([[
    local out = {}
    for _, c in ipairs(require('custom.pr_review').comments) do
      out[#out + 1] = ('%s:%d-%d %s'):format(c.path, c.start_line, c.end_line, c.body)
    end
    return out
  ]])
end

-- Review signs in the current buffer as their 1-based rows.
local function signs()
  return child.lua([[
    local ns = vim.api.nvim_get_namespaces()['user_pr_review']
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})) do
      out[#out + 1] = m[2] + 1
    end
    return out
  ]])
end

-- The review the fake `gh` received, nil when none was posted.
local function posted()
  local f = bin .. '/posted'
  return vim.uv.fs_stat(f) and vim.json.decode(table.concat(vim.fn.readfile(f), '\n')) or nil
end

-- Pushes the store and returns the posted review once the push reports back.
local function push()
  child.lua([[
    local seen = #_G.notes
    require('custom.pr_review').push()
    vim.wait(3000, function() return #_G.notes > seen end)
  ]])
  return posted()
end

-- Lines of one pane of the review window, false while it is closed.
local function pane(name)
  return child.lua([[
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.w[win].pr_review == ... then
        return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      end
    end
    return false
  ]], { name })
end

-- Presses <C-s> on the summary, picks `verdict` and waits for the report.
local function submit(verdict)
  child.lua([[
    local verdict = ...
    vim.ui.select = function(items, opts, pick)
      for _, item in ipairs(items) do
        if opts.format_item(item) == verdict then return pick(item) end
      end
      pick(nil)
    end
    _G.seen = #_G.notes
  ]], { verdict })
  child.type_keys('<C-s>')
  child.lua('vim.wait(3000, function() return #_G.notes > _G.seen end)')
  return posted()
end

T['a comment goes out on its line with the pending review'] = function()
  local sha = open_repo(new_dir())
  child.cmd('2')
  comment('', 'looks off')
  eq({ stored(), signs() }, { { 'src/a.rs:2-2 looks off' }, { 2 } })
  local posted = push()
  eq(posted, {
    commit_id = sha,
    comments = { { path = 'src/a.rs', line = 2, side = 'RIGHT', body = 'looks off' } },
  })
  -- The pushed draft leaves nothing behind.
  eq({ stored(), signs() }, { {}, {} })
end

T['a range comment spans its lines'] = function()
  open_repo(new_dir())
  comment('2,3', 'both')
  eq(push().comments, {
    { path = 'src/a.rs', start_line = 2, start_side = 'RIGHT', line = 3, side = 'RIGHT', body = 'both' },
  })
end

T[':q drops the comment'] = function()
  open_repo(new_dir())
  comment('2', 'never mind', 'q')
  eq({ stored(), signs() }, { {}, {} })
end

T['a comment follows lines added above it'] = function()
  open_repo(new_dir())
  comment('3', 'here')
  child.api.nvim_buf_set_lines(0, 0, 0, false, { 'new 1', 'new 2' })
  eq(push().comments[1].line, 5)
end

-- Before 6ddd711, the end of a comment stayed behind when a line opened right
-- above it, so the comment slid onto the new line and a range lost its end.
T['a comment keeps its lines when one opens right above'] = function()
  open_repo(new_dir())
  comment('3', 'one')
  comment('1,2', 'range')
  child.cmd('3')
  child.type_keys('Onew<Esc>', ':2<CR>', 'Onew<Esc>')
  local lines = {}
  for _, c in ipairs(push().comments) do lines[c.body] = { c.start_line, c.line } end
  eq(lines, { one = { nil, 5 }, range = { 1, 3 } })
end

T['an unsubmitted draft on github blocks the push'] = function()
  open_repo(new_dir())
  comment('2', 'later')
  local nodes = { { viewerDidAuthor = true } }
  vim.fn.writefile({ vim.json.encode({ data = { repository = { pullRequest = { reviews = { nodes = nodes } } } } }) },
    bin .. '/reviews')
  eq({ push(), stored() }, { nil, { 'src/a.rs:2-2 later' } })
end

T['a rejected push keeps the comments for a retry'] = function()
  open_repo(new_dir())
  comment('2', 'retry me')
  vim.fn.writefile({}, bin .. '/fail')
  push()
  eq(stored(), { 'src/a.rs:2-2 retry me' })
  vim.fn.delete(bin .. '/fail')
  eq(push().comments[1].body, 'retry me')
end

T['the window lists the drafts beside the selected code'] = function()
  open_repo(new_dir())
  comment('1', 'first')
  child.cmd('2,3PRReviewComment')
  eq({ pane('ctx'), pane('list') }, {
    { 'two',          'three' },
    { '  src/a.rs:1', '    first', '', '> src/a.rs:2-3  (new)', '', '  Review summary (1 comment)' },
  })
  -- The old editor was a 50x6 float at the cursor.
  local share = child.lua([[
    local width, height = 0, 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local name = vim.w[win].pr_review
      if name == 'list' or name == 'edit' then width = width + vim.api.nvim_win_get_width(win) + 2 end
      if name == 'list' then height = vim.api.nvim_win_get_height(win) + 2 end
    end
    return { width / vim.o.columns > 0.85, height / vim.o.lines > 0.75 }
  ]])
  eq(share, { true, true })
  child.type_keys('<Esc>', ':q<CR>')
  eq({ pane('list'), pane('ctx'), pane('edit'), child.fn.expand('%:t') }, { false, false, false, 'a.rs' })
end

T['<C-g> drafts a suggestion from the selected code'] = function()
  open_repo(new_dir())
  child.cmd('2,3PRReviewComment')
  child.type_keys('<C-g>')
  eq(pane('edit'), { '```suggestion', 'two', 'three', '```' })
  -- The cursor waits on the code, so typing rewrites the suggestion.
  child.type_keys('<Esc>', 'ciwtwo!<Esc>', ':wq<CR>')
  eq(stored(), { 'src/a.rs:2-3 ```suggestion\ntwo!\nthree\n```' })
end

T['a suggestion fence outgrows backticks in the code'] = function()
  open_repo(new_dir())
  child.api.nvim_buf_set_lines(0, 0, 1, false, { 'a ``` b' })
  child.cmd('1PRReviewComment')
  child.type_keys('<C-g>')
  eq(pane('edit'), { '````suggestion', 'a ``` b', '````' })
end

T['a review goes out with its summary and verdict'] = function()
  local sha = open_repo(new_dir())
  comment('2', 'looks off')
  child.cmd('PRReviewSubmit')
  eq(pane('ctx'), { '1 comment in 1 file', '  1  src/a.rs' })
  child.type_keys('needs work', '<Esc>')
  eq(submit('Request changes'), {
    commit_id = sha,
    event = 'REQUEST_CHANGES',
    body = 'needs work',
    comments = { { path = 'src/a.rs', line = 2, side = 'RIGHT', body = 'looks off' } },
  })
  eq({ stored(), signs(), pane('edit') }, { {}, {}, false })
end

T['the first <C-s> only moves to the summary'] = function()
  open_repo(new_dir())
  child.cmd('2PRReviewComment')
  child.type_keys('typed', '<C-s>')
  -- The comment in the editor is kept as a draft on the way.
  eq({ stored(), pane('edit'), posted() }, { { 'src/a.rs:2-2 typed' }, { '' }, nil })
end

T['approving needs no comments'] = function()
  local sha = open_repo(new_dir())
  child.cmd('PRReviewSubmit')
  child.type_keys('<Esc>')
  eq(submit('Approve'), { commit_id = sha, event = 'APPROVE' })
end

T['drafts are edited and deleted from the list'] = function()
  open_repo(new_dir())
  comment('1', 'first')
  comment('3', 'second')
  child.cmd('PRReviewSubmit')
  child.type_keys('<Esc>', '<Tab>', 'gg', '<CR>')
  eq({ pane('ctx'), pane('edit') }, { { 'one' }, { 'first' } })
  child.type_keys('A, reworded<Esc>', ':w<CR>')
  eq(stored(), { 'src/a.rs:1-1 first, reworded', 'src/a.rs:3-3 second' })
  child.type_keys('<Tab>', 'dd')
  eq({ stored(), child.fn.mode(), child.w.pr_review }, { { 'src/a.rs:3-3 second' }, 'n', 'list' })
  child.type_keys('q')
  eq({ pane('list'), signs() }, { false, { 3 } })
end

T['a rejected review keeps the window and the drafts'] = function()
  open_repo(new_dir())
  comment('2', 'retry me')
  vim.fn.writefile({}, bin .. '/fail')
  child.cmd('PRReviewSubmit')
  child.type_keys('summary', '<Esc>')
  eq({ submit('Comment'), stored(), pane('edit') }, { nil, { 'src/a.rs:2-2 retry me' }, { 'summary' } })
end

return T
