-- Autosave from config/autosave.lua. A change lands on disk at once, but
-- without the BufWritePre hooks (formatters) a manual :w runs.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup()
      child.lua([[
        require('config.autosave')
        -- Stands in for conform's format on save.
        _G.formatted = 0
        vim.api.nvim_create_autocmd('BufWritePre', { callback = function() _G.formatted = _G.formatted + 1 end })
      ]])
    end,
    post_once = child.stop,
  },
})

-- A file of `lines`, opened in the child.
local function open(lines)
  local file = vim.fn.tempname()
  vim.fn.writefile(lines, file)
  child.cmd('edit ' .. file)
  return file
end

T['a normal mode change is saved without the format hooks'] = function()
  local file = open({ 'one', 'two' })
  child.type_keys('dd')
  eq({ vim.fn.readfile(file), child.lua_get('_G.formatted'), child.bo.modified }, { { 'two' }, 0, false })
end

T['leaving insert mode saves what was typed'] = function()
  local file = open({ 'one' })
  child.type_keys('A!', '<Esc>')
  eq(vim.fn.readfile(file), { 'one!' })
end

T['a manual write still formats'] = function()
  open({ 'one' })
  child.cmd('write')
  eq(child.lua_get('_G.formatted'), 1)
end

T['scratch, unnamed and readonly buffers stay unwritten'] = function()
  local file = open({ 'one' })
  -- A scratch buffer named `scratch` would land in the cwd if written.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  child.cmd('cd ' .. dir)
  child.cmd('setlocal readonly')
  child.type_keys('dd')
  local readonly = vim.fn.readfile(file)
  child.cmd('enew')
  child.type_keys('ihello', '<Esc>')
  local unnamed = child.bo.modified
  child.cmd('enew | setlocal buftype=nofile | file scratch')
  child.type_keys('ihello', '<Esc>')
  eq({ readonly, unnamed, vim.fn.filereadable(dir .. '/scratch') }, { { 'one' }, true, 0 })
end

return T
