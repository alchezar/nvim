-- <Esc> closing floats. The normal-mode key from config/keys.lua, then the
-- real yazi and lazygit in their floats, where the tool itself has to quit.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'plenary.nvim', 'telescope.nvim', 'translate.nvim' } })
      child.o.lines, child.o.columns = 30, 100
      child.lua([[require('config.keys')]])
    end,
    post_once = child.stop,
  },
})

-- A focused float over a scratch buffer; `setup` runs in the child on it.
local function open_float(setup)
  return child.lua([[
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true,
      { relative = 'editor', row = 1, col = 1, width = 20, height = 3 })
    if ... then loadstring(...)(buf, win) end
    return win
  ]], { setup })
end

local function floats()
  return child.lua_get([[#vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative ~= ''
  end, vim.api.nvim_list_wins())]])
end

T['Esc closes a float that maps no key of its own'] = function()
  local main = child.api.nvim_get_current_win()
  open_float()
  child.type_keys('<Esc>')
  eq({ floats(), child.api.nvim_get_current_win() }, { 0, main })
end

T['Esc closes a float by its q mapping'] = function()
  open_float([[
    local buf, win = ...
    vim.keymap.set('n', 'q', function()
      _G.closed_by_q = true
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
  ]])
  child.type_keys('<Esc>')
  eq({ floats(), child.lua_get('_G.closed_by_q') }, { 0, true })
end

T['Esc closes a focused hover float'] = function()
  child.lua([[
    local _, win = vim.lsp.util.open_floating_preview({ 'docs' }, 'markdown', {})
    vim.api.nvim_set_current_win(win)
  ]])
  eq(floats(), 1)
  child.type_keys('<Esc>')
  eq(floats(), 0)
end

T['Esc of the float itself wins over the shared one'] = function()
  open_float([[
    local buf = ...
    vim.keymap.set('n', '<Esc>', function() _G.own_esc = true end, { buffer = buf })
  ]])
  child.type_keys('<Esc>')
  eq({ floats(), child.lua_get('_G.own_esc') }, { 1, true })
end

T['Esc leaves a split alone'] = function()
  child.cmd('vsplit')
  child.type_keys('<Esc>')
  eq(#child.api.nvim_list_wins(), 2)
end

T['Esc in a terminal float left to normal mode stops its job'] = function()
  open_float([[
    _G.job = vim.fn.jobstart({ 'sleep', '30' }, { term = true })
  ]])
  child.type_keys('<Esc>')
  local stopped = child.lua_get('vim.fn.jobwait({ _G.job }, 2000)[1] ~= -1')
  eq({ floats(), stopped }, { 0, true })
end

-- Text of the float's terminal, to tell when the tool has drawn itself.
local function wait_for(text)
  local seen = child.lua([[
    local text = ...
    return vim.wait(5000, function()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      return table.concat(lines, '\n'):find(text, 1, true) ~= nil
    end, 20)
  ]], { text })
  if not seen then error('the tool never drew "' .. text .. '"') end
  child.lua('vim.wait(200)') -- let it finish its first frame
end

-- Whether the float goes away within `ms`; the tool quitting closes it.
local function closes(ms)
  return child.lua([[
    return vim.wait(..., function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= '' then return false end
      end
      return true
    end, 20)
  ]], { ms })
end

-- Keys typed into the tool one at a time, as a lone Esc right after another
-- key reads as an Alt chord.
local function press(...)
  for _, key in ipairs({ ... }) do
    child.type_keys(key)
    child.lua('vim.wait(150)')
  end
end

local function project()
  local dir = assert(vim.uv.fs_realpath(vim.fn.tempname():match('.*/'))) .. '/'
      .. vim.fn.fnamemodify(vim.fn.tempname(), ':t')
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ 'a' }, dir .. '/alpha.txt')
  vim.fn.writefile({ 'b' }, dir .. '/beta.txt')
  child.cmd('edit ' .. dir .. '/alpha.txt')
  return dir
end

-- The quit comes from the smart-escape plugin in the real yazi config.
local function open_yazi()
  local plugin = vim.fn.expand('~/.config/yazi/plugins/smart-escape.yazi/main.lua')
  if vim.fn.executable('yazi') == 0 or vim.fn.filereadable(plugin) == 0 then
    MiniTest.skip('needs yazi with the smart-escape plugin')
  end
  project()
  child.lua([[require('config.utils').open_yazi()]])
  wait_for('beta.txt')
end

T['Esc quits yazi once nothing is left to escape'] = function()
  open_yazi()
  press('<Esc>')
  eq({ closes(3000), child.api.nvim_buf_get_name(0):match('[^/]+$') }, { true, 'alpha.txt' })
end

T['Esc in yazi clears a selection first'] = function()
  open_yazi()
  press('<Space>', '<Esc>')
  local survived = not closes(700)
  press('<Esc>')
  eq({ survived, closes(3000) }, { true, true })
end

T['Esc in yazi leaves visual mode first'] = function()
  open_yazi()
  -- Leaving visual mode keeps its files selected; the second Esc drops them.
  press('v', '<Esc>', '<Esc>')
  local survived = not closes(700)
  press('<Esc>')
  eq({ survived, closes(3000) }, { true, true })
end

T['Esc in yazi drops a filter first'] = function()
  open_yazi()
  press('f', 'b', 'e', '<CR>', '<Esc>')
  local survived = not closes(700)
  press('<Esc>')
  eq({ survived, closes(3000) }, { true, true })
end

T['Esc in yazi cancels an input without quitting'] = function()
  open_yazi()
  -- The first Esc leaves the input's insert mode, the second closes it.
  press('r', '<Esc>', '<Esc>')
  local survived = not closes(700)
  press('<Esc>')
  eq({ survived, closes(3000) }, { true, true })
end

-- Lazygit with its config and state in a temp dir, so the run neither reads
-- nor rewrites the real ones. `config` is the user's config.yml there.
local function open_lazygit(config)
  if vim.fn.executable('lazygit') == 0 then MiniTest.skip('needs lazygit') end
  local dir = project()
  vim.fn.system({ 'git', '-C', dir, 'init', '-q' })
  local home = vim.fn.tempname()
  vim.fn.mkdir(home, 'p')
  -- A state that has seen this version, or lazygit opens on its popups.
  local version = vim.fn.system({ 'lazygit', '--version' }):match('version=([%d.]+)')
  vim.fn.writefile({ 'startuppopupversion: 99', 'lastversion: ' .. version }, home .. '/state.yml')
  if config then vim.fn.writefile(config, home .. '/config.yml') end
  child.lua([[vim.env.CONFIG_DIR = ...; require('config.utils').open_lazygit()]], { home })
end

T['Esc quits lazygit once nothing is left to cancel'] = function()
  open_lazygit()
  wait_for('alpha.txt')
  press('<Esc>')
  eq(closes(3000), true)
end

T['Esc in lazygit closes a popup first'] = function()
  open_lazygit()
  wait_for('alpha.txt')
  press('?')
  wait_for('Keybindings')
  press('<Esc>')
  local survived = not closes(700)
  press('<Esc>')
  eq({ survived, closes(3000) }, { true, true })
end

T['lazygit in the float still reads the config of the user'] = function()
  open_lazygit({ 'gui:', '  language: ja' })
  wait_for('ファイル')
  press('<Esc>')
  eq(closes(3000), true)
end

return T
