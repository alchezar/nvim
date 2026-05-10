-- vim-dadbod-ui setup
-- Drawer-style sidebar listing connections, schemas, tables; query results in split.
-- Connections live in ~/.local/share/db_ui/connections.json (JSON list of {name, url}).

vim.g.db_ui_use_nerd_fonts = 1
vim.g.db_ui_show_database_icon = 1
vim.g.db_ui_force_echo_notifications = 1
vim.g.db_ui_win_position = 'right'
vim.g.db_ui_winwidth = 40
vim.g.db_ui_save_location = vim.fn.stdpath('data') .. '/db_ui/queries'
vim.g.db_ui_tmp_query_location = vim.fn.stdpath('data') .. '/db_ui/tmp'
vim.g.db_ui_execute_on_save = 0  -- don't auto-run queries on :w
vim.g.db_ui_auto_execute_table_helpers = 1  -- run Columns/Indexes/... on <CR>

-- Pick up DATABASE_URL from a project .env (via tpope/vim-dotenv) and register
-- it as a g:dbs entry. Also normalises sqlx-style URLs that dadbod can't parse:
--   * URL-decodes %xx escapes (e.g. %20 in macOS "Application Support" paths)
--   * strips query params like ?mode=rwc that sqlx accepts but sqlite3 CLI rejects
local function url_decode(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

local function normalise(url)
  url = url_decode(url)
  url = url:gsub('%?.*$', '')
  return url
end

local function pick_database_url()
  -- vim-dotenv exposes loaded vars via DotenvGet(); fall back to process env.
  local ok, val = pcall(vim.fn.DotenvGet, 'DATABASE_URL')
  if ok and val and val ~= '' then return val end
  return vim.env.DATABASE_URL
end

vim.api.nvim_create_autocmd({ 'VimEnter', 'DirChanged' }, {
  callback = function()
    -- Load .env from cwd if present (tpope/vim-dotenv).
    local env_file = vim.fn.getcwd() .. '/.env'
    if vim.fn.filereadable(env_file) == 1 then
      pcall(vim.cmd, 'Dotenv ' .. vim.fn.fnameescape(env_file))
    end
    local url = pick_database_url()
    if url and url ~= '' then
      vim.g.dbs = { project = normalise(url) }
    end
  end,
})

-- Auto-attach completion source for SQL-ish buffers managed by dadbod-ui.
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'sql', 'mysql', 'plsql' },
  callback = function()
    require('cmp').setup.buffer({
      sources = {
        { name = 'vim-dadbod-completion' },
        { name = 'buffer' },
        { name = 'path' },
      },
    })
  end,
})
