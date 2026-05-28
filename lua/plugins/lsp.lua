-- Rustaceanvim auto-configures rust-analyzer.
vim.g.rustaceanvim = {
  server = {
    settings = {
      ['rust-analyzer'] = {
        checkOnSave = true,
        -- RUSTFLAGS surfaces redundant path prefixes; rustc's unused_qualifications is allow-by-default
        -- and check.extraArgs does not reach clippy through rustaceanvim.
        check = { command = 'clippy', extraEnv = { RUSTFLAGS = '-Wunused_qualifications' } },
        cargo = { allFeatures = true },
        -- Suppress dim/underline on #[cfg]-gated branches.
        diagnostics = { disabled = { 'inactive-code' } },
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

-- #[utoipa::path] & co. expand qualified paths but stamp them with our bare token's span,
-- so unused_qualifications fires on an identifier with no `::` - an unactionable false positive.
-- Keep only hits whose flagged text actually contains `::` (the segments rustc says to remove).
local function unused_qual_actionable(uri, d)
  local r = d.range
  local bufnr = vim.uri_to_bufnr(uri)
  vim.fn.bufload(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, r.start.line, r['end'].line + 1, false)
  if not lines[1] then return true end
  local seg = #lines == 1 and lines[1]:sub(r.start.character + 1, r['end'].character)
    or table.concat(lines, '\n')
  return seg:find('::', 1, true) ~= nil
end

local rust_publish = vim.lsp.handlers['textDocument/publishDiagnostics']
vim.lsp.handlers['textDocument/publishDiagnostics'] = function(err, result, ctx)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if client and client.name == 'rust-analyzer' and result and result.diagnostics then
    result.diagnostics = vim.tbl_filter(function(d)
      local code = type(d.code) == 'table' and d.code.value or d.code
      if code ~= 'unused_qualifications' then return true end
      return unused_qual_actionable(result.uri, d)
    end, result.diagnostics)
  end
  return rust_publish(err, result, ctx)
end

-- Default capabilities for all servers (cmp_nvim_lsp).
vim.lsp.config('*', {
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})

-- TS / JS / Vue: ts_ls owns <script> via @vue/typescript-plugin.
local ts_inlay_hints = {
  includeInlayParameterNameHints = 'all',
  includeInlayFunctionParameterTypeHints = true,
  includeInlayVariableTypeHints = true,
  includeInlayPropertyDeclarationTypeHints = true,
  includeInlayFunctionLikeReturnTypeHints = true,
  includeInlayEnumMemberValueHints = true,
}
vim.lsp.config('ts_ls', {
  init_options = {
    plugins = {
      {
        name = '@vue/typescript-plugin',
        location = '/opt/homebrew/lib/node_modules/@vue/typescript-plugin',
        languages = { 'javascript', 'typescript', 'vue' },
      },
    },
  },
  filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue' },
  settings = {
    typescript = { inlayHints = ts_inlay_hints },
    javascript = { inlayHints = ts_inlay_hints },
  },
})
vim.lsp.enable('ts_ls')

-- Volar in hybrid mode: ts_ls -> TS, vue_ls -> template/style.
vim.lsp.config('vue_ls', {})
vim.lsp.enable('vue_ls')

-- ESLint: only attach when a config exists; otherwise the server spams diagnostic errors.
vim.lsp.config('eslint', {
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    local root = vim.fs.root(fname, {
      '.eslintrc', '.eslintrc.js', '.eslintrc.cjs', '.eslintrc.mjs',
      '.eslintrc.json', '.eslintrc.yaml', '.eslintrc.yml',
      'eslint.config.js', 'eslint.config.cjs', 'eslint.config.mjs',
      'eslint.config.ts',
    })
    if root then on_dir(root) end
  end,
  settings = {
    useFlatConfig = true,
    experimental = { useFlatConfig = true },
    workingDirectories = { mode = 'auto' },
  },
})
vim.lsp.enable('eslint')

-- TOML via `taplo` CLI (brew install taplo).
vim.lsp.config('taplo', {
  settings = {
    evenBetterToml = {
      schema = { enabled = true, catalogs = { 'https://www.schemastore.org/api/json/catalog.json' } },
      formatter = { alignEntries = false, alignComments = true, reorderKeys = false },
    },
  },
})
vim.lsp.enable('taplo')

-- Python: basedpyright (types) + ruff (lint/imports).
-- Resolve interpreter: $VIRTUAL_ENV -> .venv/venv in root -> system.
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
  -- Prefer Python project markers over outer .git; otherwise monorepos with nested venvs miss the venv.
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
      -- ruff owns import organization.
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

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then return end
    -- basedpyright owns hover; ruff's would shadow it.
    if client.name == 'ruff' then
      client.server_capabilities.hoverProvider = false
    end
    -- Hybrid Vue: ts_ls inlay hints use virtual-doc positions that don't map to .vue -> "Invalid 'col'".
    if vim.bo[args.buf].filetype == 'vue' and (client.name == 'ts_ls' or client.name == 'vue_ls') then
      client.server_capabilities.inlayHintProvider = false
    end
  end,
})

-- C / C++.
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

vim.lsp.codelens.enable(true)

-- Highlight separators in hover/float windows.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function(args)
    if vim.api.nvim_win_get_config(0).relative ~= '' then
      vim.fn.matchadd('FloatBorder', '^─\\+$')
      vim.fn.matchadd('Comment', '\\v(\\w+::)+')
    end
  end,
})

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = true,
  float = { border = 'rounded', source = true },
})
