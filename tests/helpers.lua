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
  -- opts.runtime puts the config itself on 'runtimepath' (colors/, queries/).
  function child.setup(opts)
    opts = opts or {}
    child.restart({ '-u', 'tests/minimal_init.lua' })
    -- Plugins and config modules keep state under data/state (bookmarks.json,
    -- logs); a child gets its own, so a run can't rewrite the real files.
    local tmp = vim.fn.tempname()
    child.lua('vim.env.XDG_DATA_HOME, vim.env.XDG_STATE_HOME = ...', { tmp .. '/data', tmp .. '/state' })
    child.lua([[
      local root, site, pack, plugins, ts, runtime = ...
      if ts then
        vim.opt.rtp:prepend(pack .. '/nvim-treesitter/runtime')
        vim.opt.rtp:prepend(site)
      end
      for _, p in ipairs(plugins) do
        vim.opt.rtp:prepend(pack .. '/' .. p)
        -- Startup already sourced plugin/ dirs; do it for the late arrivals.
        for _, f in ipairs(vim.fn.glob(pack .. '/' .. p .. '/plugin/**/*.{lua,vim}', true, true)) do
          vim.cmd.source(f)
        end
      end
      if ts or runtime then
        vim.opt.rtp:prepend(root)
        vim.opt.rtp:append(root .. '/after')
      end
    ]], { H.root, H.site, H.pack, opts.plugins or {}, opts.treesitter or false,
      opts.runtime or false })
  end

  return child
end

-- In-process fake language server attached to the child's current buffer. It
-- answers `responses[method .. ' ' .. uri .. ':' .. line]` first, else
-- `responses[method]`, so a test scripts exactly what the server "knows".
-- Its cmd stays at _G.fake_lsp_cmd, so a test can attach it again later.
function H.start_fake_lsp(child, responses, capabilities, name)
  child.lua([[
    local responses, caps, name = ...
    _G.fake_lsp_responses = responses
    _G.fake_lsp_cmd = function(dispatchers)
      local closing = false
      return {
        request = function(method, params, callback)
          local res
          if method == 'initialize' then
            res = { capabilities = caps }
          else
            local p = params or {}
            local key = p.textDocument and p.position
              and (method .. ' ' .. p.textDocument.uri .. ':' .. p.position.line)
            res = key and _G.fake_lsp_responses[key]
            if res == nil then res = _G.fake_lsp_responses[method] end
          end
          vim.schedule(function() callback(nil, res) end)
          return true, 1
        end,
        notify = function(method)
          if method == 'exit' then dispatchers.on_exit(0, 15) end
          return true
        end,
        is_closing = function() return closing end,
        terminate = function()
          if not closing then dispatchers.on_exit(0, 15) end
          closing = true
        end,
      }
    end
    vim.lsp.start({ name = name, cmd = _G.fake_lsp_cmd, root_dir = vim.fn.getcwd() })
    local ok = vim.wait(2000, function()
      return #vim.lsp.get_clients({ bufnr = 0, name = name }) > 0
    end)
    assert(ok, 'fake lsp did not attach')
  ]], { responses, capabilities, name or 'fake' })
end

return H
