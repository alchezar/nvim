-- Keymaps from config/keys.lua, checked by what they do. The clipboard is
-- faked at utils.yank_to_clipboard.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'plenary.nvim', 'telescope.nvim', 'translate.nvim' } })
      child.lua([[
        require('config.keys')
        _G.copied = {}
        require('config.utils').yank_to_clipboard = function(text) table.insert(_G.copied, text) end
      ]])
    end,
    post_once = child.stop,
  },
})

-- Before 882662f, a file opened by its absolute path, as pickers and the tree
-- open files, copied that absolute path.
T['relative path copies stay relative for a file opened by absolute path'] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/src', 'p')
  dir = vim.uv.fs_realpath(dir) or dir
  vim.fn.writefile({ 'fn main() {}' }, dir .. '/src/main.rs')
  child.lua([[
    local dir = ...
    vim.cmd.cd(dir)
    vim.cmd.edit(dir .. '/src/main.rs')
  ]], { dir })
  child.type_keys(' cr', ' cp')
  eq(child.lua_get('_G.copied'), { 'src/main.rs', 'src/main.rs:1' })
end

return T
