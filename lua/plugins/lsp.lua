-- Rustaceanvim config (auto-configures rust-analyzer)
vim.g.rustaceanvim = {
  server = {
    settings = {
      ['rust-analyzer'] = {
        checkOnSave = true,
        check = { command = 'clippy' },
        cargo = { allFeatures = true },
        semanticHighlighting = {
          strings = { enable = false },
        },
        inlayHints = {
          chainingHints = { enable = false },
        },
        lens = {
          enable = true,
          references = { adt = { enable = true }, enumVariant = { enable = true }, method = { enable = true }, trait = { enable = true } },
        },
      },
    },
  },
}

-- Default capabilities for all LSP servers (extends core with cmp_nvim_lsp)
vim.lsp.config('*', {
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})

-- TypeScript / JavaScript
local ts_inlay_hints = {
  includeInlayParameterNameHints = 'all',
  includeInlayFunctionParameterTypeHints = true,
  includeInlayVariableTypeHints = true,
  includeInlayPropertyDeclarationTypeHints = true,
  includeInlayFunctionLikeReturnTypeHints = true,
  includeInlayEnumMemberValueHints = true,
}
vim.lsp.config('ts_ls', {
  settings = {
    typescript = { inlayHints = ts_inlay_hints },
    javascript = { inlayHints = ts_inlay_hints },
  },
})
vim.lsp.enable('ts_ls')

-- ESLint
vim.lsp.config('eslint', {
  settings = {
    workingDirectories = { mode = 'auto' },
  },
})
vim.lsp.enable('eslint')

-- TOML (Cargo.toml, pyproject.toml, etc.)
-- Requires `taplo` CLI: `brew install taplo` or `cargo install taplo-cli --locked --features lsp`
vim.lsp.config('taplo', {
  settings = {
    evenBetterToml = {
      schema = { enabled = true, catalogs = { 'https://www.schemastore.org/api/json/catalog.json' } },
      formatter = { alignEntries = false, alignComments = true, reorderKeys = false },
    },
  },
})
vim.lsp.enable('taplo')

-- Python: basedpyright (types + completion) + ruff (lint + organize imports)
-- Install:
--   npm install -g basedpyright (or `pip install basedpyright`)
--   pip install ruff            (provides `ruff server` LSP)

-- basedpyright doesn't auto-discover project virtualenvs. Resolve a python in this
-- priority: active $VIRTUAL_ENV -> .venv/venv in workspace root -> nil (system).
local function find_project_python(root)
  local venv = os.getenv('VIRTUAL_ENV')
  if venv and vim.fn.executable(venv .. '/bin/python') == 1 then
    return venv .. '/bin/python'
  end
  if root then
    for _, name in ipairs({ '.venv', 'venv', '.virtualenv' }) do
      local py = root .. '/' .. name .. '/bin/python'
      if vim.fn.executable(py) == 1 then return py end
    end
  end
  return nil
end

vim.lsp.config('basedpyright', {
  -- Prefer Python project markers over the outer .git; otherwise a monorepo
  -- with nested venvs (repo_root/.git + sub/proj/.venv) anchors basedpyright at
  -- the repo root and misses the venv.
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    local root = vim.fs.root(fname, {
      'pyproject.toml', 'setup.py', 'setup.cfg',
      'pyrightconfig.json', 'Pipfile', '.venv', 'venv',
    }) or vim.fs.root(fname, { '.git' }) or vim.fn.getcwd()
    on_dir(root)
  end,
  settings = {
    basedpyright = {
      -- Let ruff own import organization
      disableOrganizeImports = true,
    },
    python = {
      analysis = {
        typeCheckingMode = 'basic',
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        diagnosticMode = 'openFilesOnly',
        inlayHints = {
          variableTypes = true,
          functionReturnTypes = true,
          callArgumentNames = true,
          pytestParameters = true,
        },
      },
    },
  },
  before_init = function(params, config)
    local root = params.workspaceFolders
      and params.workspaceFolders[1]
      and vim.uri_to_fname(params.workspaceFolders[1].uri)
      or vim.fn.getcwd()
    local py = find_project_python(root)
    if py then
      config.settings.python.pythonPath = py
    end
  end,
})
vim.lsp.enable('basedpyright')

vim.lsp.config('ruff', {})
vim.lsp.enable('ruff')

-- Let basedpyright own hover; ruff's hover is sparser and would shadow it
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.name == 'ruff' then
      client.server_capabilities.hoverProvider = false
    end
  end,
})

-- C / C++
vim.lsp.config('clangd', {
  cmd = {
    'clangd',
    '--background-index',
    '--clang-tidy',
    '--header-insertion=iwyu',
    '--completion-style=detailed',
    '--function-arg-placeholders',
    '--fallback-style=llvm',
  },
})
vim.lsp.enable('clangd')

-- Enable code lenses
vim.lsp.codelens.enable(true)

-- Highlight separator lines in hover/float windows
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(args)
    if vim.api.nvim_win_get_config(0).relative ~= '' then
      vim.fn.matchadd('FloatBorder', '^─\\+$')
      vim.fn.matchadd('Comment', '\\v(\\w+::)+')
    end
  end,
})

-- Diagnostic signs
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = true,
  float = { border = 'rounded', source = true },
})
