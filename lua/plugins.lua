vim.pack.add({
  -- Start screen
  'https://github.com/mhinz/vim-startify',

  -- LSP
  'https://github.com/neovim/nvim-lspconfig',
  'https://github.com/mrcjkb/rustaceanvim',

  -- Completion
  'https://github.com/hrsh7th/nvim-cmp',
  'https://github.com/hrsh7th/cmp-nvim-lsp',
  'https://github.com/hrsh7th/cmp-buffer',
  'https://github.com/hrsh7th/cmp-path',
  'https://github.com/hrsh7th/cmp-nvim-lsp-signature-help',
  'https://github.com/L3MON4D3/LuaSnip',
  'https://github.com/saadparwaiz1/cmp_luasnip',

  -- Treesitter
  'https://github.com/nvim-treesitter/nvim-treesitter',

  -- Debug
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/rcarriga/nvim-dap-ui',
  'https://github.com/nvim-neotest/nvim-nio',

  -- Navigation
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/nvim-telescope/telescope.nvim',
  'https://github.com/easymotion/vim-easymotion',
  'https://github.com/tpope/vim-surround',

  -- File explorer
  'https://github.com/nvim-tree/nvim-web-devicons',
  'https://github.com/nvim-tree/nvim-tree.lua',

  -- Formatting
  'https://github.com/stevearc/conform.nvim',

  -- UI / utilities
  'https://github.com/folke/trouble.nvim',
  'https://github.com/folke/todo-comments.nvim',
  'https://github.com/windwp/nvim-autopairs',
  'https://github.com/numToStr/Comment.nvim',
  'https://github.com/lewis6991/gitsigns.nvim',
  'https://github.com/lukas-reineke/virt-column.nvim',
  'https://github.com/chentoast/marks.nvim',
  'https://github.com/petertriho/nvim-scrollbar',

  -- Markdown
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',

  -- Cargo.toml: inline crate version info
  'https://github.com/Saecki/crates.nvim',

  -- Database UI (dadbod)
  'https://github.com/tpope/vim-dadbod',
  'https://github.com/kristijanhusak/vim-dadbod-ui',
  'https://github.com/kristijanhusak/vim-dadbod-completion',
  'https://github.com/tpope/vim-dotenv',
})

-- Explicitly load all plugins so require() works in init.lua
vim.cmd('packloadall')
