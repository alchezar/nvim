if not vim.g.neovide then
    return
end

vim.g.neovide_window_blurred = true
vim.g.neovide_opacity = 0.9
vim.g.neovide_normal_opacity = 0.9

-- init.lua sets Normal bg=NONE for terminal transparency, but neovide opacity
-- needs an actual bg colour to apply alpha to. Reload the scheme to restore it.
vim.cmd("colorscheme kinder_theme")
