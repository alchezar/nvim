-- Init for the test runner and every child nvim. Only the config's lua/
-- modules are requireable; plugins, colorscheme and queries stay out.
local root = vim.fn.getcwd()
package.path = ('%s/lua/?.lua;%s/lua/?/init.lua;'):format(root, root) .. package.path

vim.opt.rtp:prepend(root .. '/.deps/mini.test')
require('mini.test').setup()
