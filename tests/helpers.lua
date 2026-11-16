-- Shared test helpers. Children start clean; setup() adds back only the
-- installed plugins and parsers a test asks for (pinned by the pack lock).
local H = {}

H.root = vim.fn.getcwd()
H.site = vim.fn.stdpath('data') .. '/site'
H.pack = H.site .. '/pack/core/opt'

function H.new_child()
  local child = MiniTest.new_child_neovim()

  -- opts.plugins are paths under the pack dir; opts.treesitter adds parsers,
  -- nvim-treesitter queries and this config's queries, ordered as in real use.
  function child.setup(opts)
    opts = opts or {}
    child.restart({ '-u', 'tests/minimal_init.lua' })
    child.lua([[
      local root, site, pack, plugins, ts = ...
      if ts then
        vim.opt.rtp:prepend(pack .. '/nvim-treesitter/runtime')
        vim.opt.rtp:prepend(site)
      end
      for _, p in ipairs(plugins) do vim.opt.rtp:prepend(pack .. '/' .. p) end
      if ts then
        vim.opt.rtp:prepend(root)
        vim.opt.rtp:append(root .. '/after')
      end
    ]], { H.root, H.site, H.pack, opts.plugins or {}, opts.treesitter or false })
  end

  return child
end

return H
