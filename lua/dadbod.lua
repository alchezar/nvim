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

-- Load DATABASE_URL from cwd/.env and populate g:dbs. Exposed so the keymap
-- can call this synchronously *before* DBUI opens - otherwise g:dbs may still
-- be nil when DBUI first reads it (e.g. when <leader>du is pressed on the
-- Startify dashboard, before VimEnter fires), and the drawer caches an empty
-- connection list for the rest of the session.
local function load_dbs()
  local env_file = vim.fn.getcwd() .. '/.env'
  if vim.fn.filereadable(env_file) == 1 then
    pcall(vim.cmd, 'Dotenv ' .. vim.fn.fnameescape(env_file))
  end
  local url = pick_database_url()
  if url and url ~= '' then
    vim.g.dbs = { project = normalise(url) }
  end
end

vim.api.nvim_create_autocmd('DirChanged', { callback = load_dbs })
vim.api.nvim_create_user_command('DBUIOpen', function()
  load_dbs()
  vim.cmd('DBUIToggle')
end, { desc = 'Reload .env and toggle DBUI drawer' })

-- Show query results (filetype=dbout) in a centered floating window instead of
-- the bottom split dadbod opens by default. Floating gives much more vertical
-- room for wide result tables and keeps the layout clean (similar to yazi).
local function is_floating(win)
  return vim.api.nvim_win_get_config(win).relative ~= ''
end

local function open_dbout_floating(buf)
  local width  = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines   * 0.85)
  vim.api.nvim_open_win(buf, true, {
    relative    = 'editor',
    width       = width,
    height      = height,
    row         = math.floor((vim.o.lines   - height) / 2) - 1,
    col         = math.floor((vim.o.columns - width)  / 2),
    border      = 'rounded',
    title       = ' Query result (q / <Esc> to close) ',
    title_pos   = 'center',
    style       = 'minimal',
  })
  vim.keymap.set('n', 'q',     '<cmd>close<CR>', { buffer = buf, silent = true, nowait = true })
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf, silent = true, nowait = true })
end

vim.api.nvim_create_autocmd('BufWinEnter', {
  callback = function(args)
    if vim.bo[args.buf].filetype ~= 'dbout' then return end
    -- Already in a floating window (e.g. user re-entered) - do nothing.
    if is_floating(vim.api.nvim_get_current_win()) then return end
    -- Close every non-floating window currently showing this dbout buffer,
    -- then re-show it floating.
    for _, w in ipairs(vim.fn.win_findbuf(args.buf)) do
      if not is_floating(w) then pcall(vim.api.nvim_win_close, w, false) end
    end
    open_dbout_floating(args.buf)
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
