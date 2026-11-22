-- Which files hex.nvim opens as an xxd dump, per plugins/hex_setup.lua. Only
-- binaries and images do; text in any encoding stays text.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'hex.nvim' } })
      child.lua([[require('plugins.hex_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Opens a file named `name` holding raw `bytes`; true when it shows as hex.
local function opens_as_hex(name, bytes)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local f = assert(io.open(dir .. '/' .. name, 'wb'))
  f:write(bytes)
  f:close()
  child.cmd('edit ' .. vim.fn.fnameescape(dir .. '/' .. name))
  local first = child.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  return child.lua_get('vim.b.hex == true') and first:match('^00000000:') ~= nil
end

T['images and build outputs open as hex'] = function()
  eq({ opens_as_hex('logo.png', '\137PNG\r\n\26\n'), opens_as_hex('a.out', 'x\0y') }, { true, true })
end

T['an extensionless executable is told by its magic bytes'] = function()
  eq({
    elf = opens_as_hex('tool', '\127ELF\2\1\1\0'),
    macho = opens_as_hex('app', '\207\250\237\254\7\0\0\1'),
    pe = opens_as_hex('setup', 'MZ\144\0\3\0'),
    text = opens_as_hex('notes', 'plain words\n'),
  }, { elf = true, macho = true, pe = true, text = false })
end

-- Before 4dbd9e7, any file that was not utf-8 opened as hex, as a shell
-- history with one latin1 byte does.
T['text that is not utf-8 stays text'] = function()
  eq(opens_as_hex('.zsh_history', ': 1700000000:0;echo caf\233\n'), false)
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { ': 1700000000:0;echo café' })
end

return T
