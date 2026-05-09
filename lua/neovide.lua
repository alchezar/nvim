if not vim.g.neovide then
    return
end

vim.g.neovide_window_blurred = true
vim.g.neovide_opacity = 0.9
vim.g.neovide_normal_opacity = 0.9
vim.g.neovide_input_macos_option_key_is_meta = "both"
vim.g.neovide_hide_mouse_when_typing = true

-- Font settings. My own font with concinese name.
-- Based on the Iosevka Font. https://typeof.net/Iosevka/
vim.opt.guifont = "Iosevka Chill Nerd:h16"
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

local update_cursor_color = require("utils").update_cursor_color
vim.opt.guicursor = "n-v-c-sm:block-Cursor,i-ci-ve:ver25-Cursor,r-cr-o:hor20-Cursor"
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
