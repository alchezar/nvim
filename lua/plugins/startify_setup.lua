-- vim-startify dashboard. Project paths come from lua/config/projects.lua (gitignored).

local function load_projects()
  local ok, projects = pcall(require, 'config.projects')
  return ok and projects or {}
end

-- Per-project entry: `tcd <path> | Startify` so Recent/Sessions refresh against the new cwd.
-- Avoids Startify's change_to_dir/vcs_root which cd'd from the buffer's git root, not the bookmark.
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

-- Startify's `type` field needs a Funcref, not a `v:lua...` string.
vim.cmd([[
  function! g:StartifyProjects() abort
    return luaeval('_G.startify_projects()')
  endfunction
]])

-- Hide empty sections.
vim.g.startify_enable_special = 0

vim.api.nvim_create_autocmd('User', {
  pattern  = 'StartifyReady',
  callback = function()
    vim.wo.wrap = false
  end,
})

local content_width = 85

-- Center against full editor width, then subtract the window's left col so
-- the layout lands at the same screen position with or without the file tree.
local function apply_layout(win_col)
  local total_w = vim.o.columns
  local pad_n   = math.max(4, math.floor((total_w - content_width) / 2) - (win_col or 0))
  local pad     = string.rep(' ', pad_n)

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
  callback = function() apply_layout(0) end,
})

-- On resize: update padding via the patch function and re-render cow/headers/items.
vim.api.nvim_create_autocmd('WinResized', {
  callback = function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'startify' then
        local win_col = vim.api.nvim_win_get_position(win)[2]
        local pad_n   = apply_layout(win_col)
        vim.fn['startify#set_padding'](pad_n)
        vim.api.nvim_win_call(win, function() vim.cmd('Startify') end)
        break
      end
    end
  end,
})
