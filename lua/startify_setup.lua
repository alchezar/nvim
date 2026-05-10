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

-- Startify's `type` field accepts a Funcref, not a `v:lua...` string. Wrap the
-- lua function in a vimscript shim so it can be referenced via `function(...)`.
vim.cmd([[
  function! g:StartifyProjects() abort
    return luaeval('_G.startify_projects()')
  endfunction
  let g:startify_lists = [
    \ { 'type': function('g:StartifyProjects'), 'header': ['   Projects']     },
    \ { 'type': 'files',                        'header': ['   Recent files'] },
    \ { 'type': 'sessions',                     'header': ['   Sessions']     },
    \ { 'type': 'commands',                     'header': ['   Commands']     },
    \ ]
]])

-- Hide empty sections
vim.g.startify_enable_special = 0
