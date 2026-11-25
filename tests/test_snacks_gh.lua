-- snacks.gh derives its diff colors from the float foreground when it loads.
-- kinder_theme leaves Normal without one, which plugins/snacks_setup covers.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ runtime = true, plugins = { 'snacks.nvim' } })
      child.cmd('colorscheme kinder_theme')
      child.lua([[require('plugins.snacks_setup')]])
    end,
    post_once = child.stop,
  },
})

-- Before bf03ee3, loading it blended a nil foreground and the gh_pr finder
-- failed with "Finder not found".
T['the gh module loads with no fg in the diff groups either'] = function()
  eq(child.lua_get([[vim.api.nvim_get_hl(0, { name = 'Normal' }).fg == nil]]), true)
  -- The diff groups come first in snacks' lookup; strip their fg too, so only
  -- the config's own SnacksGhNormalFloat can answer.
  child.lua([[
    for _, g in ipairs({ 'DiffAdd', 'DiffDelete', 'DiffChange', 'NormalFloat' }) do
      vim.api.nvim_set_hl(0, g, { bg = '#202020' })
    end
  ]])
  local ok, err = unpack(child.lua([[
    local ok, err = pcall(require, 'snacks.gh')
    return { ok, tostring(err) }
  ]]))
  eq({ ok, ok and '' or err }, { true, '' })
end

-- What the GitHub menu offers and which snacks source the answer `pick`
-- opens; the sources are spies, so no gh call leaves the child.
local function menu(pick)
  return child.lua([[
    local pick = ...
    local snacks = require('snacks')
    local opened = {}
    snacks.picker.gh_pr = function() table.insert(opened, 'gh_pr') end
    snacks.picker.gh_issue = function() table.insert(opened, 'gh_issue') end
    local offered
    vim.ui.select = function(items, opts, done)
      offered = vim.tbl_map(opts.format_item, items)
      done(pick ~= vim.NIL and items[vim.fn.index(offered, pick) + 1] or nil)
    end
    require('config.utils').github_menu()
    return { offered = offered, opened = opened }
  ]], { pick or vim.NIL })
end

T['the github menu opens the source picked, and nothing on cancel'] = function()
  eq({ menu('Issues'), menu('Pull Requests'), menu().opened }, {
    { offered = { 'Pull Requests', 'Issues' }, opened = { 'gh_issue' } },
    { offered = { 'Pull Requests', 'Issues' }, opened = { 'gh_pr' } },
    {},
  })
end

return T
