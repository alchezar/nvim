-- Make vim motions work with the Ukrainian ЙЦУКЕН layout enabled.
-- ЙЦУКЕН chars in QWERTY key order: upper row first, then lower.
local ua = [[ҐЙЦУКЕНГШЩЗХЇ/ФІВАПРОЛДЖЄЯЧСМИТЬБЮ,ґйцукенгшщзхїфівапролджєячсмитьбю.]]

require('langmapper').setup({
  use_layouts = { 'ua' },
  layouts = {
    ua = { id = 'com.apple.keylayout.Ukrainian-PC', layout = ua },
  },
})

-- langmapper only maps builtin operators in normal mode; native langmap covers
-- them in visual/operator-pending too (it leaves insert/cmdline text alone).
local en = require('langmapper.config').config.default_layout
local en_chars = vim.fn.split(en, '\\zs')
local ua_chars = vim.fn.split(ua, '\\zs')
local function esc(ch) return ch:match('[,;\\]') and '\\' .. ch or ch end
-- ; : " are handled by layout-aware keymaps below, so keep them out of langmap
-- (langmap can't tell the Ukrainian key from the QWERTY one printing the same char).
local handled = { [';'] = true, [':'] = true, ['"'] = true }
local lm = {}
for i, lat in ipairs(en_chars) do
  local cyr = ua_chars[i]
  -- Only remap keys whose typed char is non-ASCII. ASCII chars (/ , . etc.) exist
  -- in QWERTY too, so langmap can't tell layouts apart and would hijack the
  -- English command (e.g. mapping `;`->`$` also breaks `:` and `;`).
  if cyr and cyr ~= lat and cyr:byte(1) > 127 and not handled[lat] then
    lm[#lm + 1] = esc(cyr) .. esc(lat)
  end
end
-- Ukrainian Shift+3 prints № (non-ASCII, unused in vim) -> safe to map to # directly.
lm[#lm + 1] = '№#'
vim.opt.langmap = table.concat(lm, ',')

-- These keys print the same char in both layouts but sit on different physical
-- keys, so langmap can't disambiguate. Resolve by the active layout instead.
local u = require('config.utils')
local motion = { 'n', 'x', 'o' }
local cmd = { 'n', 'x' }
vim.keymap.set(motion, ';', u.key_dollar, { expr = true, desc = 'UA Shift+4 -> $, else ; (repeat f/t)' })
vim.keymap.set(motion, ':', u.key_caret, { expr = true, desc = 'UA Shift+6 -> ^, else : (command)' })
vim.keymap.set(cmd, '"', u.key_at, { expr = true, desc = 'UA Shift+2 -> @, else " (register)' })
-- Restore each freed command on its Ukrainian Cyrillic key.
vim.keymap.set(motion, 'ж', ';', { desc = 'repeat f/t (Ukrainian ; key)' })
vim.keymap.set(cmd, 'Ж', ':', { desc = 'command mode (Ukrainian : key)' })
vim.keymap.set(cmd, 'Є', '"', { desc = 'register prefix (Ukrainian " key)' })
u.watch_kbd_layout()
