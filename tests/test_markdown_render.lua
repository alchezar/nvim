-- markview plus the config's own word-wrapped table renderer, checked by what
-- the screen shows under 'wrap' (the config's default for markdown).
local H = require('tests.helpers')
local new_set = MiniTest.new_set
local expect = MiniTest.expect
local child = H.new_child()

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({
        treesitter = true,
        plugins = { 'nvim-web-devicons', 'markview.nvim' },
      })
      child.o.lines, child.o.columns = 16, 50
      -- No statusline or ruler: the temp file name would change every run.
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

-- Before 33954a1, with no row below the table there was nowhere to hang its
-- bottom.
T['table at the end of the file is closed'] = function()
  open(WIDE)
  shot()
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
  MiniTest.expect.equality(missing, {})
end

-- Before 926bf2b, wrapped rows of a list item got markview's padding on top.
T['wrapped list item lines up with its text'] = function()
  open({ '- ' .. ('item text '):rep(8), '', ('plain prose '):rep(6) })
  shot()
end

-- Before 731bd8f, the 'block' style padded lines to the widest one, and under
-- wrap the padding spilled into rows of stray background.
T['code block under wrap'] = function()
  open({ '```lua', 'local x = 1', 'print("' .. ('x'):rep(60) .. '")', '```' })
  shot()
end

-- Before ce15fcc, punctuation, nested markup and block quotes broke the wrapped
-- box.
T['table with markup inside a quote'] = function()
  open({
    '> | Key | Value |',
    '> | --- | --- |',
    '> | **bold**, `code` | a note, with commas; and *more* text than fits |',
  })
  shot()
end

-- Before dcfee7f, an emoji with VS16 measured 3 cells while wrapping, not 2,
-- and the rows past it overran the border. Asserted on border columns, since
-- screenshot files drop VS16 and a reference can't hold it.
T['emoji with VS16 keeps the border straight'] = function()
  local e = '\u{26A0}\u{FE0F}'
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
  MiniTest.expect.equality(#rows > 2, true)
  for _, r in ipairs(rows) do MiniTest.expect.equality(r, rows[1]) end
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

-- Before 862dd6e, a repaint during insert mode (a resize, an option set) put
-- the preview back over the line being edited.
T['insert mode stays raw through a resize'] = function()
  open(WIDE)
  child.type_keys('3G', 'A', ' more')
  child.o.columns = 48
  settle()
  shot()
  child.type_keys('<Esc>')
end

-- Before 4292ff8, hover and preview floats are nofile buffers markview must
-- skip.
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
  shot()
end

-- Before 76cc84e, a new sign narrowed the text area with no event, and the box
-- kept its old width.
T['table refits when a sign appears'] = function()
  open(WIDE)
  child.lua([[
    vim.wo.signcolumn = 'auto'
    local ns = vim.api.nvim_create_namespace('test_sign')
    vim.api.nvim_buf_set_extmark(0, ns, 0, 0, { sign_text = 'S' })
  ]])
  settle()
  shot()
end

return T
