-- Telescope pickers as plugins/telescope_setup.lua shapes them. LSP rows lead
-- with the code and trail the mirrored path, references mark their access.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ treesitter = true, plugins = { 'plenary.nvim', 'telescope.nvim' } })
      child.o.lines, child.o.columns = 30, 160
      child.lua([[require('plugins.telescope_setup')]])
    end,
    post_once = child.stop,
  },
})

-- A project with `src/a.rs`, opened with a fake server that answers
-- `method` with the uses of `x` on lines 2 and 3.
local function project(method, cap)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. '/src', 'p')
  dir = assert(vim.uv.fs_realpath(dir))
  vim.fn.writefile({ 'fn f(mut x: u8) -> u8 {', '    x = 1;', '    x', '}' }, dir .. '/src/a.rs')
  child.lua('vim.cmd.cd(...)', { dir })
  child.cmd('edit src/a.rs')
  local uri = vim.uri_from_fname(dir .. '/src/a.rs')
  local function at(line)
    return { uri = uri, range = { start = { line = line, character = 4 }, ['end'] = { line = line, character = 5 } } }
  end
  H.start_fake_lsp(child, { [method] = { at(1), at(2) } }, { [cap] = true })
  child.api.nvim_win_set_cursor(0, { 1, 9 })
  return dir
end

-- Rows of the picker `open` starts, once it has any.
local function picker(open)
  return child.lua([[
    loadstring(...)()
    local rows
    vim.wait(2000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(w)
        if vim.bo[b].filetype == 'TelescopeResults' then
          -- A list that grows upward pads its top with blank rows.
          rows = vim.tbl_filter(function(r) return r ~= '' end, vim.api.nvim_buf_get_lines(b, 0, -1, false))
          return #rows > 0
        end
      end
    end)
    return rows
  ]], { open })
end

-- Mode once the picker settled; insert mode starts only between requests.
local function mode()
  child.lua('vim.wait(100)')
  return child.api.nvim_get_mode().mode
end

T['a row leads with its code, then the file, then its dirs mirrored'] = function()
  project('textDocument/definition', 'definitionProvider')
  eq(picker([[require('telescope.builtin').lsp_definitions()]]),
    { '> x = 1;  a.rs:2:5\\src', '  x  a.rs:3:5\\src' })
end

T['reference rows mark a write and a read'] = function()
  project('textDocument/references', 'referencesProvider')
  local marks = {}
  for _, row in ipairs(picker([[require('telescope.builtin').lsp_references()]])) do
    marks[row:match('%d:5')] = row:match('^. (%S+)')
  end
  eq(marks, { ['2:5'] = '↓', ['3:5'] = '↑' })
end

T['pickers open in normal mode, live grep in insert'] = function()
  local dir = project('textDocument/definition', 'definitionProvider')
  picker([[require('telescope.builtin').find_files()]])
  local files = mode()
  child.type_keys('<Esc>')
  child.lua(([[require('telescope.builtin').live_grep({ cwd = %q })]]):format(dir))
  local grep = mode()
  eq({ files, grep }, { 'n', 'i' })
end

T['dd closes the buffer under the cursor and keeps the picker'] = function()
  local dir = project('textDocument/definition', 'definitionProvider')
  vim.fn.writefile({ 'b' }, dir .. '/src/b.rs')
  child.cmd('edit src/b.rs')
  local before = #picker([[require('telescope.builtin').buffers()]])
  -- Normal mode, whichever mode the picker opened in.
  child.cmd('stopinsert')
  child.type_keys('dd')
  child.lua('vim.wait(200)')
  local listed = #vim.tbl_filter(function(b) return child.api.nvim_buf_get_option(b, 'buflisted') end,
    child.api.nvim_list_bufs())
  eq({ before, listed, picker('')[1] ~= nil }, { 2, 1, true })
end

return T
