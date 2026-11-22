-- Startup layout from config/startup.lua: the tree on the left and the shared
-- right panel, unless the session is a throwaway one.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true, plugins = { 'nvim-web-devicons', 'nvim-tree.lua' } })
      child.o.lines, child.o.columns = 30, 160
      child.lua([[
        vim.cmd.cd(...)
        require('plugins.file-tree')
        require('config.startup')
      ]], { vim.fn.tempname():match('^(.*)/') })
    end,
    post_once = child.stop,
  },
})

-- Window filetypes left to right once startup has run, and the focused one.
-- A test child has no UI, so one is faked unless `headless`.
local function layout(headless)
  return child.lua([[
    if not ... then vim.api.nvim_list_uis = function() return { { rgb = true } } end end
    vim.cmd('doautocmd VimEnter')
    vim.wait(1000, function() return #vim.api.nvim_tabpage_list_wins(0) > 2 end)
    vim.wait(100)
    local wins = vim.api.nvim_tabpage_list_wins(0)
    table.sort(wins, function(a, b) return vim.fn.win_screenpos(a)[2] < vim.fn.win_screenpos(b)[2] end)
    local fts = vim.tbl_map(function(w) return vim.bo[vim.api.nvim_win_get_buf(w)].filetype end, wins)
    return { wins = fts, focus = vim.bo.filetype }
  ]], { headless or false })
end

T['a session opens the tree and the panel, focus stays in the editor'] = function()
  child.cmd('setlocal filetype=rust')
  eq(layout(), { wins = { 'NvimTree', 'rust', 'HoverPanel' }, focus = 'rust' })
end

T['a commit message keeps the bare window'] = function()
  child.cmd('setlocal filetype=gitcommit')
  eq(layout(), { wins = { 'gitcommit' }, focus = 'gitcommit' })
end

T['a diff session keeps its windows'] = function()
  child.o.diff = true
  eq(layout(), { wins = { '' }, focus = '' })
end

T['a headless run keeps the bare window'] = function()
  eq(layout(true), { wins = { '' }, focus = '' })
end

T['a tree already open stays open'] = function()
  child.lua([[require('nvim-tree.api').tree.open()]])
  child.cmd('wincmd l')
  eq(layout().wins, { 'NvimTree', '', 'HoverPanel' })
end

return T
