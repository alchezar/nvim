-- nvim-dbee: drawer sidebar with inline columns; connections from project .env DATABASE_URL.

local dbee = require('dbee')
local sources = require('dbee.sources')
local theme = require('config.theme_colors')

-- Dim the `[type]` suffix on column nodes so the name reads as primary.
local function apply_drawer_highlights()
  vim.api.nvim_set_hl(0, 'DbeeColumnType', { fg = theme.silver })
end
apply_drawer_highlights()
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_drawer_highlights })

-- Connection source: cwd/.env DATABASE_URL exposed as one "project" connection.
-- Re-fetches on DirChanged via dbee.api.core.source_reload.
local function url_decode(s)
  return (s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

-- URL-decode (%20 in macOS paths) and default postgres to sslmode=disable
-- so lib/pq accepts local servers with SSL off.
local function normalise(url)
  url = url_decode(url)
  local scheme = (url:match('^([%w]+):') or ''):lower()
  if (scheme == 'postgres' or scheme == 'postgresql') and not url:match('[?&]sslmode=') then
    url = url .. (url:find('?', 1, true) and '&' or '?') .. 'sslmode=disable'
  end
  return url
end

local function infer_type(url)
  local scheme = (url:match('^([%w]+):') or ''):lower()
  if scheme == 'postgres' or scheme == 'postgresql' then return 'postgres' end
  if scheme == 'mysql'    or scheme == 'mariadb'    then return 'mysql'    end
  if scheme == 'sqlite'   or scheme == 'sqlite3'    then return 'sqlite'   end
  return nil
end

local function pick_database_url()
  local ok, val = pcall(vim.fn.DotenvGet, 'DATABASE_URL')
  if ok and val and val ~= '' then return val end
  return vim.env.DATABASE_URL
end

-- Re-reads g:dbee_project_url on every load() so source_reload picks up .env changes.
local ProjectEnvSource = { id = 'project_env' }
ProjectEnvSource.__index = ProjectEnvSource

function ProjectEnvSource:new()
  return setmetatable({}, self)
end

function ProjectEnvSource:name()
  return 'project'
end

function ProjectEnvSource:load()
  local url = vim.g.dbee_project_url
  if not url or url == '' then return {} end
  local conn_type = infer_type(url)
  if not conn_type then
    vim.schedule(function()
      vim.notify('Dbee: unsupported DATABASE_URL scheme; skipping project connection',
        vim.log.levels.WARN)
    end)
    return {}
  end
  return {
    {
      id = 'project_env',
      name = 'project',
      type = conn_type,
      url = url,
    },
  }
end

-- Load .env into g:dbee_project_url and reload the source. Sync-callable from keymap.
local function load_dbs()
  local env_file = vim.fn.getcwd() .. '/.env'
  if vim.fn.filereadable(env_file) == 1 then
    pcall(vim.cmd, 'Dotenv ' .. vim.fn.fnameescape(env_file))
  end
  local url = pick_database_url()
  vim.g.dbee_project_url = url and url ~= '' and normalise(url) or nil
  -- Skip reload until the Go backend is installed; otherwise DirChanged spams logs.
  if vim.fn.executable('dbee') == 1 then
    -- source_reload takes the source's name(), not the connection id.
    pcall(function() require('dbee').api.core.source_reload('project') end)
  end
end

vim.api.nvim_create_autocmd('DirChanged', { callback = load_dbs })

-- Layout: drawer = 40-col vsplit right; editor / result / call_log = floats.
local function open_float(width_pct, height_pct, title)
  local width  = math.floor(vim.o.columns * width_pct)
  local height = math.floor(vim.o.lines   * height_pct)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative  = 'editor',
    width     = width,
    height    = height,
    row       = math.floor((vim.o.lines   - height) / 2) - 1,
    col       = math.floor((vim.o.columns - width)  / 2),
    border    = 'rounded',
    title     = title,
    title_pos = 'center',
    style     = 'minimal',
    hide      = true,
  })
  return win
end

local FloatLayout = {}
FloatLayout.__index = FloatLayout

function FloatLayout:new() return setmetatable({}, self) end

function FloatLayout:is_open()
  return self.drawer_win ~= nil and vim.api.nvim_win_is_valid(self.drawer_win)
end

local function set_hide(win, hide)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_config, win, { hide = hide })
  end
end

-- q / <Esc> on a float hides instead of closing.
local function bind_hide_keys(winid, hide_fn)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then return end
  local buf = vim.api.nvim_win_get_buf(winid)
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set('n', 'q',     hide_fn, opts)
  vim.keymap.set('n', '<Esc>', hide_fn, opts)
end

-- (Re)create floats and bind dbee UI. dbee's *_show un-hides ignoring our hide=true,
-- so we re-hide explicitly after the call.
function FloatLayout:_setup_editor_float()
  self.editor_win = open_float(0.7, 0.7, ' SQL editor (q / <Esc> to hide) ')
  require('dbee.api.ui').editor_show(self.editor_win)
  set_hide(self.editor_win, true)
  bind_hide_keys(self.editor_win, function() self:hide_editor() end)
end

function FloatLayout:_setup_result_float()
  self.result_win = open_float(0.9, 0.85, ' Query result (q / <Esc> to hide) ')
  require('dbee.api.ui').result_show(self.result_win)
  set_hide(self.result_win, true)
  bind_hide_keys(self.result_win, function() self:hide_result() end)
end

function FloatLayout:_setup_log_float()
  self.log_win = open_float(0.6, 0.4, ' Call log (q / <Esc> to hide) ')
  require('dbee.api.ui').call_log_show(self.log_win)
  set_hide(self.log_win, true)
  bind_hide_keys(self.log_win, function() self:hide_call_log() end)
end

-- Tracks prev focused window per-float so hide returns focus there.
local function show_float(self, key, setup_method)
  local cur = vim.api.nvim_get_current_win()
  if not (self[key] and vim.api.nvim_win_is_valid(self[key])) then
    setup_method(self)
  end
  -- Never record the float as its own _prev (auto-show on second query fires here).
  if cur ~= self[key] then self['_prev_' .. key] = cur end
  set_hide(self[key], false)
  vim.api.nvim_set_current_win(self[key])
end

local function hide_float(self, key)
  set_hide(self[key], true)
  local prev = self['_prev_' .. key]
  if prev and prev ~= self[key] and vim.api.nvim_win_is_valid(prev) then
    vim.api.nvim_set_current_win(prev)
    return
  end
  -- Fallback: drawer -> origin window.
  for _, w in ipairs({ self.drawer_win, self.origin_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
end

function FloatLayout:show_editor()   show_float(self, 'editor_win', self._setup_editor_float) end
function FloatLayout:hide_editor()   hide_float(self, 'editor_win') end
function FloatLayout:show_result()   show_float(self, 'result_win', self._setup_result_float) end
function FloatLayout:hide_result()   hide_float(self, 'result_win') end
function FloatLayout:show_call_log() show_float(self, 'log_win',    self._setup_log_float)    end
function FloatLayout:hide_call_log() hide_float(self, 'log_win') end

function FloatLayout:open()
  self.origin_win = vim.api.nvim_get_current_win()

  vim.cmd('botright 40vsplit')
  self.drawer_win = vim.api.nvim_get_current_win()
  require('dbee.api.ui').drawer_show(self.drawer_win)
  -- Drawer-local list=false so the visual-mode listchars expansion (init.lua) doesn't dot-fill it.
  vim.wo[self.drawer_win].list = false
  vim.api.nvim_buf_call(vim.api.nvim_win_get_buf(self.drawer_win), function()
    vim.cmd('syntax match DbeeColumnType /\\[[^\\]]*\\]$/')
  end)

  self:_setup_editor_float()
  self:_setup_result_float()
  -- Call log float is lazy on <leader>dq; binding it here would un-hide on every log entry.

  vim.api.nvim_set_current_win(self.origin_win)
end

function FloatLayout:close()
  for _, w in ipairs({ self.editor_win, self.result_win, self.log_win, self.drawer_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  self.origin_win, self.drawer_win = nil, nil
  self.editor_win, self.result_win, self.log_win = nil, nil, nil
end

function FloatLayout:reset() end

load_dbs()

local layout = FloatLayout:new()

dbee.setup({
  sources = {
    sources.FileSource:new(vim.fn.stdpath('data') .. '/dbee/connections.json'),
  },
  window_layout = layout,
  drawer = { window_options = { number = false, relativenumber = false, signcolumn = 'no' } },
  result = { page_size = 100 },
  editor = { directory = vim.fn.stdpath('data') .. '/dbee/notes' },
})

-- NuiTree drawer indents by shiftwidth; keep tight to fit a 40-col panel.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'dbee',
  callback = function() vim.bo.shiftwidth = 2 end,
})

-- Back-compat command for old <leader>d* keymaps that call DBUI*.
vim.api.nvim_create_user_command('DBUIOpen', function()
  load_dbs()
  dbee.toggle()
end, { desc = 'Reload .env and toggle Dbee UI' })

-- cmp-dbee completion for SQL buffers.
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'sql', 'mysql', 'plsql' },
  callback = function()
    require('cmp').setup.buffer({
      sources = {
        { name = 'cmp-dbee' },
        { name = 'buffer' },
        { name = 'path' },
      },
    })
  end,
})

pcall(function() require('cmp-dbee').setup() end)

-- Register ProjectEnvSource after setup so a failure doesn't abort the rest.
local ok, err = pcall(function() dbee.api.core.add_source(ProjectEnvSource:new()) end)
if not ok then
  vim.schedule(function()
    vim.notify('Dbee: failed to register project source: ' .. tostring(err), vim.log.levels.WARN)
  end)
end

-- Auto-show result float on any query (covers drawer helper menus that bypass dbee_run).
pcall(function()
  dbee.api.core.register_event_listener('call_state_changed', function(data)
    local ok = pcall(function()
      if data and data.call and data.call.state == 'executing' and layout:is_open() then
        vim.schedule(function() pcall(function() layout:show_result() end) end)
      end
    end)
    if not ok then vim.schedule(function() vim.notify('dbee listener error', vim.log.levels.DEBUG) end) end
  end)
end)

return {
  layout = layout,
  show_editor   = function() layout:show_editor()   end,
  hide_editor   = function() layout:hide_editor()   end,
  show_result   = function() layout:show_result()   end,
  hide_result   = function() layout:hide_result()   end,
  show_call_log = function() layout:show_call_log() end,
}
