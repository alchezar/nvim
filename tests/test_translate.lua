-- translate.nvim through plugins/translate_setup.lua, with a fake `curl` in
-- place of Google. Paragraphs come back joined, the float wraps and fits them.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

-- The fake answers `reply` (lines, JSON-encoded like the service's own answer)
-- whatever it was asked.
local function fake_curl(reply)
  local bin = vim.fn.tempname()
  vim.fn.mkdir(bin, 'p')
  vim.fn.writefile({ vim.json.encode(reply) }, bin .. '/reply.txt')
  vim.fn.writefile({ '#!/bin/sh', 'cat "' .. bin .. '/reply.txt"' }, bin .. '/curl')
  vim.fn.setfperm(bin .. '/curl', 'rwxr-xr-x')
  return bin
end

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'translate.nvim' } })
      child.o.lines, child.o.columns = 30, 60
      child.lua([[require('plugins.translate_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Translate every line of `source`; returns the float's lines and geometry.
local function translate(source, reply)
  child.lua('vim.env.PATH = ... .. ":" .. vim.env.PATH', { fake_curl(reply) })
  child.api.nvim_buf_set_lines(0, 0, -1, false, source)
  -- The way the visual-mode mapping runs it.
  child.type_keys('gg', 'VG')
  child.lua([[require('plugins.translate_setup').translate_selection('uk')]])
  return child.lua([[
    local win
    vim.wait(3000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= '' then win = w end
      end
      return win ~= nil
    end)
    assert(win, 'no translation float')
    local buf = vim.api.nvim_win_get_buf(win)
    return {
      lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
      text_height = vim.api.nvim_win_text_height(win, { start_row = 0 }).all,
      wrap = vim.wo[win].wrap,
      breakindent = vim.wo[win].breakindent,
    }
  ]])
end

-- Before 0e181eb, the stock parser cut the translation back to the source's
-- line widths character by character, splitting words.
T['each paragraph comes back as one line'] = function()
  local got = translate({ 'first line', 'of a paragraph', '', 'second' },
    { 'перший рядок', 'абзацу', '', 'другий' })
  eq(got.lines, { 'перший рядок абзацу', '', 'другий' })
end

-- Before a13776e a long line ran off the screen.
T['long translation wraps inside the screen'] = function()
  local got = translate({ 'long text' }, { ('слово '):rep(40) })
  eq({ wrap = got.wrap, fits_screen = got.width <= 48 }, { wrap = true, fits_screen = true })
end

-- Before 34b81cb the height was width-divided text, but word wrap leaves the
-- row ends short, so the float cut off the last rows.
T['float is as tall as the wrapped text'] = function()
  local word = ('w'):rep(20)
  local got = translate({ 'long text' }, { vim.trim((word .. ' '):rep(20)) })
  eq({ got.height, got.text_height >= 10 }, { got.text_height, true })
end

return T
