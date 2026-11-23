-- plugins/debugging.lua against a fake debug adapter served over TCP inside
-- the child: dap-ui follows the session, and a C++ launch asks for its
-- program and args.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'nvim-nio', 'nvim-dap', 'nvim-dap-ui' } })
      child.o.lines, child.o.columns = 40, 160
      child.lua([[
        require('plugins.debugging')
        -- Answers every request and says `initialized` after `initialize`.
        _G.requests = {}
        local server = vim.uv.new_tcp()
        server:bind('127.0.0.1', 0)
        server:listen(1, function()
          local sock, buf, seq = vim.uv.new_tcp(), '', 0
          server:accept(sock)
          local function send(msg)
            seq = seq + 1
            msg.seq = seq
            local body = vim.json.encode(msg)
            sock:write(('Content-Length: %d\r\n\r\n%s'):format(#body, body))
          end
          _G.adapter_send = send
          sock:read_start(function(_, chunk)
            if not chunk then return end
            buf = buf .. chunk
            while true do
              local len, at = buf:match('^Content%-Length: (%d+)\r\n\r\n()')
              if not len or #buf < at + len - 1 then break end
              local msg = vim.json.decode(buf:sub(at, at + len - 1))
              buf = buf:sub(at + len)
              _G.requests[#_G.requests + 1] = msg
              send({ type = 'response', request_seq = msg.seq, success = true, command = msg.command, body = {} })
              if msg.command == 'initialize' then send({ type = 'event', event = 'initialized' }) end
            end
          end)
        end)
        require('dap').adapters.codelldb = { type = 'server', host = '127.0.0.1', port = server:getsockname().port }
        -- The prompts of the launch config, answered by prompt text.
        vim.fn.input = function(prompt, default)
          return prompt:find('Args') and ' one  two ' or default .. 'app'
        end
      ]])
    end,
    post_once = child.stop,
  },
})

-- Filetypes of the dap-ui windows on screen.
local function ui()
  return child.lua([[
    local fts = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
      if ft:find('^dapui_') then fts[#fts + 1] = ft end
    end
    table.sort(fts)
    return fts
  ]])
end

local function launch()
  child.lua([[
    require('dap').run(require('dap').configurations.cpp[1])
    vim.wait(3000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'dapui_scopes' then return true end
      end
    end)
  ]])
end

T['dap-ui opens with the session and closes when it ends'] = function()
  launch()
  local opened = ui()
  child.lua([[
    _G.adapter_send({ type = 'event', event = 'terminated' })
    vim.wait(3000, function() return require('dap').session() == nil end)
    vim.wait(100)
  ]])
  eq({ opened, ui() }, {
    { 'dapui_breakpoints', 'dapui_console', 'dapui_scopes', 'dapui_stacks', 'dapui_watches' },
    {},
  })
end

-- Before 8019e92, two spaces between args passed an empty one between them.
T['a c++ launch sends the program and the args it asked for'] = function()
  launch()
  local args = child.lua([[
    for _, r in ipairs(_G.requests) do
      if r.command == 'launch' then return r.arguments end
    end
  ]])
  eq({ args.program, args.args }, { child.fn.getcwd() .. '/build/app', { 'one', 'two' } })
end

return T
