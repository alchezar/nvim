-- markview plus the config's own word-wrapped table renderer, checked by what
-- the screen shows under 'wrap' (the config's default for markdown). Most fixes
-- are asserted on a screen property, since a screenshot taken today also
-- differs at old revisions for unrelated reasons.
local H = require('tests.helpers')
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({
        treesitter = true,
        plugins = { 'nvim-web-devicons', 'markview.nvim' },
      })
      child.o.lines, child.o.columns = 16, 50
      -- No statusline or ruler, since the temp file name changes every run.
      child.o.laststatus, child.o.ruler, child.o.showcmd = 0, false, false
      child.lua([[
        vim.o.wrap, vim.o.linebreak, vim.o.breakindent = true, true, true
        require('plugins.markdown')
      ]])
    end,
    post_once = child.stop,
  },
})

-- Run the callbacks queued so far and the ones they queue, then redraw.
local function settle()
  child.lua([[
    for _ = 1, 3 do
      local done = false
      vim.schedule(function() done = true end)
      vim.wait(1000, function() return done end)
    end
    vim.cmd('redraw')
  ]])
end

local function edit(lines)
  local file = vim.fn.tempname() .. '.md'
  vim.fn.writefile(lines, file)
  child.cmd('edit ' .. file)
end

-- Open a markdown file and wait until markview or the table box has drawn it.
local function open(lines)
  edit(lines)
  child.lua([[
    vim.wait(2000, function()
      for name, id in pairs(vim.api.nvim_get_namespaces()) do
        if (name:match('^markview') or name == 'kinder_md_table_wrap')
            and #vim.api.nvim_buf_get_extmarks(0, id, 0, -1, {}) > 0 then
          return true
        end
      end
      return false
    end)
  ]])
  settle()
end

local function shot() expect.reference_screenshot(child.get_screenshot()) end

-- Screen text, one string per row.
local function screen()
  return child.lua([[
    vim.cmd('redraw')
    local rows = {}
    for r = 1, vim.o.lines do
      local cells = {}
      for c = 1, vim.o.columns do cells[c] = vim.fn.screenstring(r, c) end
      rows[r] = table.concat(cells)
    end
    return rows
  ]])
end

local function has(rows, text)
  for _, row in ipairs(rows) do
    if row:find(text, 1, true) then return true end
  end
  return false
end

-- Screen rows once ok(rows) holds, or as they are after a second.
local function wait_screen(ok)
  local rows = screen()
  for _ = 1, 20 do
    if ok(rows) then break end
    vim.uv.sleep(50)
    rows = screen()
  end
  return rows
end

local function boxed(rows) return has(rows, '╭') end

local function words(text)
  local out = {}
  for w in text:gmatch('%w+') do out[#out + 1] = w end
  return out
end

-- Words drawn for buffer line `lnum`, in screen order. A word broken across
-- two rows comes out as two.
local function drawn_words(lnum)
  return child.lua([[
    vim.cmd('redraw')
    local lnum = ...
    local first = vim.fn.screenpos(0, lnum, 1).row
    local height = vim.api.nvim_win_text_height(0, { start_row = lnum - 1, end_row = lnum - 1 }).all
    local out = {}
    for r = first, first + height - 1 do
      local cells = {}
      for c = 1, vim.o.columns do cells[c] = vim.fn.screenstring(r, c) end
      for w in table.concat(cells):gmatch('%w+') do out[#out + 1] = w end
    end
    return out
  ]], { lnum })
end

local WIDE = {
  '| Name | Notes |',
  '| --- | --- |',
  '| alpha | a long note that cannot fit in one row of this narrow window |',
  '| beta | short |',
}

-- Before a7036e9, markview's condition fix made it attach to nothing at all.
T['wide table wraps words inside the box'] = function()
  open(vim.list_extend(vim.deepcopy(WIDE), { '', 'after' }))
  shot()
end

T['table at the end of the file is closed'] = function()
  open(WIDE)
  shot()
end

-- Before 33954a1, a table ending the file lost its bottom border under wrap.
-- The border hung below the last row, where nvim never scrolls.
T['tall table ending the file shows its bottom border'] = function()
  local lines = { '| Row | Note |', '| --- | --- |' }
  for i = 1, 30 do lines[#lines + 1] = ('| r%02d | x |'):format(i) end
  open(lines)
  child.type_keys('G')
  eq(has(wait_screen(function(rows) return has(rows, '╰') end), '╰'), true)
end

-- Before 33954a1, markview's own table put its bottom border on the row below,
-- which isn't there when the table ends the file.
T['table at the end of the file is closed without wrap'] = function()
  open(WIDE)
  child.lua([[vim.wo.wrap = false]])
  local rows = wait_screen(function(r) return has(r, '╰') and not boxed(r) end)
  eq(has(rows, '╰'), true)
end

-- Before e8e6c69, the whole box hung off one row as a single virt_lines block,
-- and scrolling past that row skipped the rest of a tall table.
T['scrolling a tall table shows every row'] = function()
  local lines = { 'top', '', '| Row | Note |', '| --- | --- |' }
  for i = 1, 60 do lines[#lines + 1] = ('| r%02d | x |'):format(i) end
  open(vim.list_extend(lines, { '', 'end' }))
  -- Walk down with <C-e> and collect the row labels shown on screen. The
  -- cursor's screen row is left out because it may show the raw source.
  local seen = child.lua([[
    local seen = {}
    vim.cmd('normal! gg')
    for _ = 1, 400 do
      vim.cmd('redraw')
      local cursor = vim.fn.winline()
      for row = 1, vim.api.nvim_win_get_height(0) do
        if row ~= cursor then
          local text = {}
          for col = 1, vim.o.columns do text[col] = vim.fn.screenstring(row, col) end
          for label in table.concat(text):gmatch('r%d%d') do seen[label] = true end
        end
      end
      local view = vim.fn.winsaveview()
      vim.cmd.normal({ args = { vim.keycode('<C-e>') }, bang = true })
      local now = vim.fn.winsaveview()
      if now.topline == view.topline and now.topfill == view.topfill then break end
    end
    return seen
  ]])
  local missing = {}
  for i = 1, 60 do
    local label = ('r%02d'):format(i)
    if not seen[label] then missing[#missing + 1] = label end
  end
  eq(missing, {})
end

-- Before 926bf2b, wrapped rows of a list item got markview's padding on top.
T['wrapped list item lines up with its text'] = function()
  open({ '- ' .. ('item text '):rep(8), '', ('plain prose '):rep(6) })
  shot()
end

-- Before d52ea71, nothing turned 'linebreak' on for markdown, so prose wrapped
-- mid-word.
T['prose breaks between words without a linebreak of its own'] = function()
  child.o.linebreak = false
  local prose = ('plain prose '):rep(6)
  open({ 'top', '', prose })
  eq(drawn_words(3), words(prose))
end

-- Before d52ea71, hidden markup in prose was concealed to spaces, a width only
-- table rows need, which left gaps around the bold word.
T['bold prose shows no gaps where its stars hid'] = function()
  open({ 'top', '', 'plain **bold** words' })
  eq(has(screen(), 'plain bold words'), true)
end

-- Before 7ef41e5, the markdown ftplugin's 't' broke lines at 'textwidth'
-- while typing. 5212f2d moved the fix into config/options.lua.
T['typing a long line keeps it whole'] = function()
  child.lua([[require('config.options')]])
  edit({ '' })
  child.type_keys('i', ('word '):rep(20), '<Esc>')
  eq(#child.api.nvim_buf_get_lines(0, 0, -1, false), 1)
end

-- Before 731bd8f, the 'block' style padded lines to the widest one, and under
-- wrap the padding spilled into rows of stray background.
T['code block under wrap'] = function()
  open({ '```lua', 'local x = 1', 'print("' .. ('x'):rep(60) .. '")', '```' })
  shot()
end

-- Before ce15fcc, a quoted table's later rows parsed to no cells, and markup
-- next to punctuation broke apart or kept its asterisks.
T['table with markup inside a quote'] = function()
  open({
    '> | Key | Value |',
    '> | --- | --- |',
    '> | **bold**, `code` | a note, with commas; and *more* text than fits |',
    '> | two | second |',
  })
  local rows = screen()
  eq({
    later_row = has(rows, 'second'),
    punctuation = has(rows, 'bold,'),
    asterisks = has(rows, '*'),
  }, { later_row = true, punctuation = true, asterisks = false })
  shot()
end

-- Before dcfee7f, an emoji with VS16 was measured codepoint by codepoint while
-- wrapping, so U+1F6E1 plus VS16 took 3 cells, not 2, and later rows overran
-- the border. Asserted on border columns, as screenshot files drop VS16.
T['emoji with VS16 keeps the border straight'] = function()
  local e = '\u{1F6E1}\u{FE0F}'
  open({ '| Flag | Meaning |', '| --- | --- |', '| x | ' .. (e .. ' warn '):rep(8) .. '|' })
  local rows = child.lua([[
    local out = {}
    for row = 1, vim.o.lines do
      local cols = {}
      for col = 1, vim.o.columns do
        if vim.fn.screenstring(row, col) == '\u{2502}' then cols[#cols + 1] = col end
      end
      if #cols > 0 then out[#out + 1] = table.concat(cols, ',') end
    end
    return out
  ]])
  eq(#rows > 2, true)
  for _, r in ipairs(rows) do eq(r, rows[1]) end
end

-- Before 53d039a, without wrap markview sized the column with the link's hidden
-- label, leaving the cell padded far too wide.
T['reference link width without wrap'] = function()
  open({
    '| Doc | Link |',
    '| --- | --- |',
    '| guide | [the guide][a-rather-long-reference-label] |',
    '',
    '[a-rather-long-reference-label]: https://example.com',
  })
  child.lua([[vim.wo.wrap = false]])
  settle()
  shot()
end

-- Before 80e6a14, markview cleared only its own marks on insert, so the box
-- stayed next to the raw rows being edited. Text above the table gives the old
-- single-block box a row to hang from.
T['insert mode clears the box'] = function()
  open(vim.list_extend({ 'top', '' }, WIDE))
  child.type_keys('5G', 'i')
  local rows = wait_screen(function(r) return not boxed(r) end)
  eq({ box = boxed(rows), raw = has(rows, '| alpha |') }, { box = false, raw = true })
  child.type_keys('<Esc>')
end

-- Before 862dd6e, a repaint during insert mode, such as a resize, put the box
-- back over the line being edited.
T['insert mode stays raw through a resize'] = function()
  open(WIDE)
  child.type_keys('3G', 'A', ' more')
  child.o.columns = 48
  settle()
  local rows = screen()
  eq({ box = boxed(rows), raw = has(rows, '| alpha |') }, { box = false, raw = true })
  shot()
  child.type_keys('<Esc>')
end

-- Before 2a6e68e, a sideways scroll kept markview's table, whose border drifts
-- there. The raw rows keep their columns, as hidden markup conceals to spaces.
T['sideways scroll shows the raw table in line'] = function()
  child.o.wrap = false
  open({ '| Key      | Value |', '| -------- | ----- |', '| **bold** | x     |' })
  child.lua([[vim.cmd('normal! zl')]])
  local rows = wait_screen(function(r) return not has(r, '│') end)
  -- Columns of every '|' on each of the three table rows.
  local cols = {}
  for i = 1, 3 do
    local found = {}
    for pos in rows[i]:gmatch('()|') do found[#found + 1] = pos end
    cols[i] = table.concat(found, ',')
  end
  eq(has(rows, '│'), false)
  eq(cols[1] ~= '', true)
  eq({ cols[2], cols[3] }, { cols[1], cols[1] })
end

-- Before bd7b766, turning wrap on in a sideways scroll kept the table raw.
-- Both states counted as raw, so going from one to the other never repainted.
-- markview now repaints on OptionSet by itself; noautocmd keeps that out and
-- leaves the scroll back to column 0 as the only trigger.
T['wrap turned on in a sideways scroll draws the box'] = function()
  child.o.wrap = false
  open(vim.list_extend(vim.deepcopy(WIDE), { '', 'after' }))
  child.lua([[vim.cmd('normal! 3G10zl')]])
  wait_screen(function(r) return not has(r, '│') end)
  child.lua([[vim.cmd('noautocmd setlocal wrap')]])
  eq(boxed(wait_screen(boxed)), true)
end

-- Before 4292ff8, the config's own repaint drew markview into nofile floats,
-- such as LSP hover, which markview itself never attaches to.
T['nofile float stays raw'] = function()
  edit({ 'text' })
  settle()
  child.lua([[
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# Title', '**bold**' })
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 3, col = 5, width = 20, height = 3 })
  ]])
  settle()
  -- A markview heading would hide the '#' behind its own icon.
  eq(has(screen(), '# Title'), true)
  shot()
end

-- Before 76cc84e, a new sign narrowed the text area with no event, and the box
-- kept its old width, cut off at the window's edge.
T['table refits when a sign appears'] = function()
  open(WIDE)
  child.lua([[
    vim.wo.signcolumn = 'auto'
    local ns = vim.api.nvim_create_namespace('test_sign')
    vim.api.nvim_buf_set_extmark(0, ns, 0, 0, { sign_text = 'S' })
  ]])
  eq(has(wait_screen(function(rows) return has(rows, '╮') end), '╮'), true)
  shot()
end

return T
