-- File-tree icons. Defined entries override nvim-web-devicons defaults;
-- everything else falls back to the plugin's built-in icon set.

local theme = require('config.theme_colors')

local M = {}

-- Per filename (exact match, takes priority over extension).
M.by_filename = {
  ['mod.rs']             = { icon = '\u{e68b}', color = theme.orange, name = 'RustMod'       },  -- 
  ['.env']               = { icon = '\u{f084}', color = theme.yellow, name = 'Env'           },  -- 
  ['.env.example']       = { icon = '\u{f43d}', color = theme.silver, name = 'EnvExample'    },  -- 
  ['.gitignore']         = { icon = '\u{e65d}', color = theme.red,    name = 'GitIgnore'     },  --  
  ['.gitattributes']     = { icon = '\u{e65d}', color = theme.pink,   name = 'GitAttributes' },  --  
  ['Makefile']           = { icon = '\u{e673}', color = theme.green,  name = 'Makefile'      },  -- 
  ['LICENSE']            = { icon = '\u{ebe9}', color = theme.yellow, name = 'License'       },  --  
  ['.dockerignore']      = { icon = '\u{f21f}', color = theme.blue,   name = 'DockerIgnore'  },  -- 
  ['docker-compose.yml'] = { icon = '\u{f21f}', color = theme.blue,   name = 'DockerCompose' },  -- 
  ['Dockerfile']         = { icon = '\u{f21f}', color = theme.blue,   name = 'Dockerfile'    },  -- 
  ['vite.config.ts']     = { icon = '\u{f013}', color = theme.orange, name = 'ViteConfigTs'  },  -- 
}

-- Per extension.
M.by_extension = {
  sql      = { icon = '\u{f1c0}',  color = theme.cyan,   name = 'Sql'      },  -- 
  db       = { icon = '\u{f1c0}',  color = theme.cyan,   name = 'Db'       },  -- 
  sqlite   = { icon = '\u{f1c0}',  color = theme.cyan,   name = 'Sqlite'   },  -- 
  sqlite3  = { icon = '\u{f1c0}',  color = theme.cyan,   name = 'Sqlite3'  },  --  
  toml     = { icon = '\u{f013}',  color = theme.orange, name = 'Toml'     },  --  
  lock     = { icon = '\u{f0675}', color = theme.silver, name = 'Lock'     },  -- 󰙵
  exe      = { icon = '\u{f2db}',  color = theme.cyan,   name = 'Exe'      },  -- 
  bin      = { icon = '\u{f2db}',  color = theme.cyan,   name = 'Bin'      },  -- 
  out      = { icon = '\u{f2db}',  color = theme.cyan,   name = 'Out'      },  -- 
  sh       = { icon = '\u{f489}',  color = theme.green,  name = 'Sh'       },  -- 
  yml      = { icon = '\u{ef70}',  color = theme.silver, name = 'Yml'      },  -- 
  yaml     = { icon = '\u{ef70}',  color = theme.silver, name = 'Yaml'     },  -- 
  css      = { icon = '\u{f13c}',  color = theme.blue,   name = 'Css'      },  -- 
}

function M.setup()
  require('nvim-web-devicons').setup({
    override_by_filename  = M.by_filename,
    override_by_extension = M.by_extension,
    default = true,
  })
end

return M
