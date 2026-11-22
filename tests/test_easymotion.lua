-- plugins/easymotion_setup.lua: `s` jumps by a two-char search, and while the
-- labels stand in the text, diagnostics and gitsigns signs are paused.
local H = require('tests.helpers')
local eq = MiniTest.expect.equality
local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.setup({ plugins = { 'vim-easymotion', 'gitsigns.nvim' } })
      child.lua([[
        require('gitsigns').setup()
        require('plugins.easymotion_setup')
        -- Registered after the config's own handlers, so it sees their result.
        _G.seen = {}
        for _, ev in ipairs({ 'EasyMotionPromptBegin', 'EasyMotionPromptEnd' }) do
          vim.api.nvim_create_autocmd('User', { pattern = ev, callback = function()
            _G.seen[#_G.seen + 1] = {
              ev, vim.diagnostic.is_enabled(), require('gitsigns.config').config.signcolumn,
            }
          end })
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T['labels pause diagnostics and signs until the jump lands'] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { 'start', 'one ab', 'two ab' })
  child.type_keys('s', 'a', 'b')
  -- The label of the second target, read while it stands in the text.
  local label = child.api.nvim_buf_get_lines(0, 2, 3, false)[1]:sub(5, 5)
  child.type_keys(label)
  eq(child.lua_get('_G.seen'), {
    { 'EasyMotionPromptBegin', false, false },
    { 'EasyMotionPromptEnd',   true,  true },
  })
  eq(child.api.nvim_win_get_cursor(0), { 3, 4 })
end

return T
