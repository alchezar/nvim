if not vim.g.neovide then
  return
end

vim.g.neovide_window_blurred = true
vim.g.neovide_opacity = 0.9
vim.g.neovide_normal_opacity = 0.9
vim.g.neovide_input_macos_option_key_is_meta = "both"
vim.g.neovide_hide_mouse_when_typing = true
vim.g.neovide_cursor_trail_size = 0.8

vim.g.neovide_cursor_smooth_blink = false
vim.g.neovide_cursor_animate_in_insert_mode = true
vim.g.neovide_cursor_animate_command_line = true

-- vim.g.neovide_position_animation_length = 0
vim.g.neovide_floating_shadow = false

-- Font settings. My own font with concinese name.
-- Based on the Iosevka Font. https://typeof.net/Iosevka/
vim.opt.guifont = "Iosevka Chill Nerd Medium:h17"
vim.opt.linespace = -4;
-- Set color scheme. My own color theme with a concine name.
-- Based on the MonokaiPro(Spectrum) and OneDarkPro color themes.
vim.cmd("colorscheme kinder_theme")

-- Theme tweaks specific to Neovide:
--  - Solid background (terminal nvim stays transparent)
--  - Block cursor takes the color of the character underneath
local function apply_neovide_theme()
  local bg = "#262626"
  vim.api.nvim_set_hl(0, "Normal", { bg = bg })
  vim.api.nvim_set_hl(0, "NormalFloat", { bg = bg })
end

local update_cursor_color = require("config.utils").update_cursor_color
vim.opt.guicursor =
"n-v-c-sm:block-Cursor-blinkwait500-blinkoff500-blinkon500,i-ci-ve:ver25-Cursor-blinkwait500-blinkoff500-blinkon500,r-cr-o:hor20-Cursor"
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
  callback = update_cursor_color,
})

vim.api.nvim_create_autocmd({ "ColorScheme" }, {
  callback = function()
    apply_neovide_theme()
    update_cursor_color()
  end,
})
apply_neovide_theme()
update_cursor_color()
