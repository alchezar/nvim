if not vim.g.neovide then
    return
end

vim.g.neovide_window_blurred = true
vim.g.neovide_opacity = 0.9
vim.g.neovide_normal_opacity = 0.9
vim.g.neovide_input_macos_option_key_is_meta = "both"

-- Font settings. My own font with concinese name.
-- Based on the Iosevka Font. https://typeof.net/Iosevka/
vim.opt.guifont = "Iosevka Chill Nerd:h16"
-- Set color scheme. My own color theme with a concine name. 
-- Based on the MonokaiPro(Spectrum) and OneDarkPro color themes.
vim.cmd("colorscheme kinder_theme")
