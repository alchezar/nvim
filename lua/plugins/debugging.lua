local dap = require('dap')
local dapui = require('dapui')

dapui.setup()

-- Auto open/close DAP UI
dap.listeners.after.event_initialized['dapui_config'] = function() dapui.open() end
dap.listeners.before.event_terminated['dapui_config'] = function() dapui.close() end
dap.listeners.before.event_exited['dapui_config'] = function() dapui.close() end

-- CodeLLDB adapter
-- Install: download from https://github.com/vadimcn/codelldb/releases
-- Extract to ~/.local/share/codelldb/
local codelldb_path = vim.fn.expand('~/.local/share/codelldb/extension/adapter/codelldb')

dap.adapters.codelldb = {
  type = 'server',
  port = '${port}',
  executable = {
    command = codelldb_path,
    args = { '--port', '${port}' },
  },
}

dap.configurations.rust = {
  {
    name = 'Launch',
    type = 'codelldb',
    request = 'launch',
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
  },
}

dap.configurations.cpp = {
  {
    name = 'Launch',
    type = 'codelldb',
    request = 'launch',
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/build/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    args = function()
      local input = vim.fn.input('Args (space-separated): ')
      return vim.split(input, ' ', { trimempty = true })
    end,
  },
}

dap.configurations.c = dap.configurations.cpp

-- Python: debugpy lives in a dedicated venv so it's available regardless of
-- which interpreter the project uses. Setup:
--   python3 -m venv ~/.virtualenvs/debugpy
--   ~/.virtualenvs/debugpy/bin/pip install debugpy
-- For each project, $VIRTUAL_ENV (or python interpreter via `:Py`) is respected
-- at runtime - this path is only where debugpy itself is imported from.
local debugpy_python = vim.fn.expand('~/.virtualenvs/debugpy/bin/python')
local ok_py, dap_python = pcall(require, 'dap-python')
if ok_py and vim.fn.executable(debugpy_python) == 1 then
  dap_python.setup(debugpy_python)
end
