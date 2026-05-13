-- vim-startify dashboard config

-- Project paths live in lua/projects.lua (gitignored). Fall back to an empty
-- list if the file is missing (e.g. fresh clone on a new machine).
local function load_projects()
  local ok, projects = pcall(require, 'projects')
  return ok and projects or {}
end

-- Custom list entry per project: `tcd` to the path, then re-open Startify so
-- the Recent files / Sessions sections refresh against the new cwd. Going via
-- a per-entry `cmd` avoids Startify's change_to_dir / change_to_vcs_root logic,
-- which mis-cd'd from the current buffer's git root instead of the bookmark.
function _G.startify_projects()
  local entries = {}
  for _, item in ipairs(load_projects()) do
    local path, name
    if type(item) == 'string' then
      path = item
      name = vim.fn.fnamemodify(path, ':t')
    else
      path = item.path
      name = item.name or vim.fn.fnamemodify(path, ':t')
    end
    table.insert(entries, {
      line = name,
      cmd  = 'tcd ' .. vim.fn.fnameescape(path) .. ' | Startify',
    })
  end
  return entries
end

-- Startify's `type` field accepts a Funcref, not a `v:lua...` string.
vim.cmd([[
  function! g:StartifyProjects() abort
    return luaeval('_G.startify_projects()')
  endfunction
]])

-- Hide empty sections
vim.g.startify_enable_special = 0

vim.api.nvim_create_autocmd('User', {
  pattern  = 'StartifyReady',
  callback = function()
    vim.wo.colorcolumn = ''
    vim.wo.wrap        = false
  end,
})

local content_width = 85

local function apply_layout(win_w)
  local pad_n = math.max(4, math.floor((win_w - content_width) / 2))
  local pad   = string.rep(' ', pad_n)

  vim.g.startify_pad_str      = pad
  vim.g.startify_padding_left = pad_n
  vim.g.startify_custom_header =
    "map(startify#fortune#cowsay(), 'g:startify_pad_str . v:val')"
  vim.g.startify_files_number = 100 - #load_projects()

  vim.cmd(string.format([[
    let g:startify_lists = [
      \ { 'type': function('g:StartifyProjects'), 'header': ['%s   Projects']     },
      \ { 'type': 'files',                        'header': ['%s   Recent files'] },
      \ { 'type': 'sessions',                     'header': ['%s   Sessions']     },
      \ { 'type': 'commands',                     'header': ['%s   Commands']     },
      \ ]
  ]], pad, pad, pad, pad))

  return pad_n
end

vim.api.nvim_create_autocmd('VimEnter', {
  once     = true,
  callback = function() apply_layout(vim.o.columns) end,
})

-- On window resize, update s:leftpad/s:fixed_column via the patch function,
-- then re-render so all three layers (cow, headers, items) use the new width.
vim.api.nvim_create_autocmd('WinResized', {
  callback = function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'startify' then
        local pad_n = apply_layout(vim.api.nvim_win_get_width(win))
        vim.fn['startify#set_padding'](pad_n)
        vim.api.nvim_win_call(win, function() vim.cmd('Startify') end)
        break
      end
    end
  end,
})
