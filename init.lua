require("config.options")                 -- Editor settings: numbers, indent, search, listchars
require("config.neovide")                 -- Neovide GUI: font, opacity, title bar
require('plugins.visual_multi_setup')     -- Multi-cursor; must load before plugins
require("config.plugins")                 -- Bootstrap plugin manager and plugin list
require("plugins.langmapper_setup")       -- Ukrainian layout twins; before any keymaps
require("config.autosave")                -- Auto-save buffers on change/focus loss
require("config.keys")                    -- Global keymaps
require("plugins.telescope_setup")        -- Fuzzy finder
require("plugins.lsp")                    -- Language servers + LSP keymaps
require("plugins.completion_setup")       -- Autocompletion engine
require("plugins.treesitter")             -- Syntax parsing and highlighting
require("plugins.plpgsql_highlight")      -- Lexical fallback highlight inside $$...$$ bodies
require("plugins.debugging")              -- DAP debug adapters + UI
require("plugins.formatting")             -- Format-on-save (conform)
require("plugins.translate_setup")        -- Translate text in the buffer
require("custom.axum_routes")             -- Telescope picker for axum/utoipa routes
require('plugins.autopairs_setup')        -- Auto-close brackets and quotes
require('Comment').setup()                -- gc/gcc comment toggling
require('gitsigns').setup()               -- Git change signs in the gutter
require('plugins.todo_comments_setup')    -- Highlight TODO/NOTE; tag colors from palette
require('trouble').setup()                -- Diagnostics/quickfix list UI
require('plugins.fidget_setup')           -- LSP progress spinner
require('plugins.file-tree')              -- File explorer sidebar
require('config.tree_icons').setup()      -- Custom file-tree icons by filename
require('plugins.virt_column_setup')      -- Column rulers at 80/100 (visual/insert)
require('plugins.highlight_colors_setup') -- Color literals as background swatches
require('custom.bookmarks')               -- Line bookmarks as extmarks
require('custom.trailing_whitespace')     -- Trailing whitespace as HINT diagnostics
require('plugins.markdown')               -- Markdown in-buffer rendering
require('plugins.csvview_setup')          -- Render CSV as aligned tables
require('plugins.fishbone_setup')         -- Bookmark mark layer in the gutter
require('plugins.dbee')                   -- Database client UI
require('plugins.blame_setup')            -- Inline git blame
require('plugins.diffview_setup')         -- Git diff and history viewer
require('plugins.snacks_setup')           -- Snacks picker: GitHub PR/issue sources
require('custom.branch_review')           -- :ReviewMode - gutter + tree marks vs branch base
require('custom.pr_review')               -- Local PR review: collect comments, push as draft
require('custom.feature_tree')            -- Virtual feature/layer tree + [f/]f layer switcher
require('custom.float_backdrop')          -- Dim + blur editor behind dialog floats
require('plugins.startify_setup')         -- Start screen / dashboard
require('plugins.crates_setup')           -- Cargo.toml crate versions
require('plugins.hex_setup')              -- Open binaries in xxd hex view
require('config.filetypes')               -- Custom filetype detection
require('plugins.easymotion_setup')       -- Jump to motions via labels
