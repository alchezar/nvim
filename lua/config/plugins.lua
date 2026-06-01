vim.pack.add({
  'https://github.com/mhinz/vim-startify',                        -- Start screen
  'https://github.com/neovim/nvim-lspconfig',                     -- LSP
  'https://github.com/mrcjkb/rustaceanvim',                       --
  'https://github.com/j-hui/fidget.nvim',                         --
  'https://github.com/hrsh7th/nvim-cmp',                          -- Completion
  'https://github.com/hrsh7th/cmp-nvim-lsp',                      --
  'https://github.com/hrsh7th/cmp-buffer',                        --
  'https://github.com/hrsh7th/cmp-path',                          --
  'https://github.com/hrsh7th/cmp-nvim-lsp-signature-help',       --
  'https://github.com/L3MON4D3/LuaSnip',                          --
  'https://github.com/saadparwaiz1/cmp_luasnip',                  --
  'https://github.com/hrsh7th/cmp-cmdline',                       -- Cmdline completion
  'https://github.com/nvim-treesitter/nvim-treesitter',           -- Treesitter
  'https://github.com/mfussenegger/nvim-dap',                     -- Debug
  'https://github.com/rcarriga/nvim-dap-ui',                      --
  'https://github.com/nvim-neotest/nvim-nio',                     --
  'https://github.com/mfussenegger/nvim-dap-python',              --
  'https://github.com/nvim-lua/plenary.nvim',                     -- Navigation
  'https://github.com/nvim-telescope/telescope.nvim',             --
  'https://github.com/easymotion/vim-easymotion',                 --
  'https://github.com/tpope/vim-surround',                        --
  'https://github.com/tpope/vim-sleuth',                          --
  'https://github.com/mg979/vim-visual-multi',                    --
  'https://github.com/uga-rosa/translate.nvim',                   --
  'https://github.com/nvim-tree/nvim-web-devicons',               -- File explorer
  'https://github.com/nvim-tree/nvim-tree.lua',                   --
  'https://github.com/stevearc/conform.nvim',                     -- Formatting
  'https://github.com/folke/trouble.nvim',                        -- UI / utilities
  'https://github.com/folke/todo-comments.nvim',                  --
  'https://github.com/windwp/nvim-autopairs',                     --
  'https://github.com/numToStr/Comment.nvim',                     --
  'https://github.com/lewis6991/gitsigns.nvim',                   --
  'https://github.com/lukas-reineke/virt-column.nvim',            --
  'https://github.com/chentoast/marks.nvim',                      -- Letter marks a-z/A-Z signs (numbered 0-9 are our own module)
  'https://github.com/alchezar/fishbone.nvim',                    --
  'https://github.com/brenoprata10/nvim-highlight-colors',        -- Inline color preview for #hex / rgb / hsl
  'https://github.com/MeanderingProgrammer/render-markdown.nvim', -- Markdown
  'https://github.com/Saecki/crates.nvim',                        -- Cargo.toml: inline crate version info
  'https://github.com/MunifTanjim/nui.nvim',                      -- Database UI (nvim-dbee)
  'https://github.com/kndndrj/nvim-dbee',                         --
  'https://github.com/MattiasMTS/cmp-dbee',                       --
  'https://github.com/tpope/vim-dotenv',                          --
  'https://github.com/FabijanZulj/blame.nvim',                    -- Git blame side panel with date heatmap
  'https://github.com/sindrets/diffview.nvim',                    -- Diff / 3-way merge conflict resolution
  'https://github.com/RaafatTurki/hex.nvim',                      -- Hex view for binary files (images, .bin, etc.)
  'https://github.com/kdheepak/lazygit.nvim',                     -- Lazygit integration (floating terminal)
  'https://github.com/Wansmer/langmapper.nvim',                   -- Vim motions with Ukrainian keyboard layout
})

-- Explicitly load all plugins so require() works in init.lua
vim.cmd('packloadall')
