-- blame.nvim: side-panel git blame with red->green HSL date heat-map. Keymaps in keys.lua.

local theme = require('config.theme_colors')

local function hex_to_rgb(hex)
  hex = hex:gsub('#', '')
  return tonumber(hex:sub(1, 2), 16),
      tonumber(hex:sub(3, 4), 16),
      tonumber(hex:sub(5, 6), 16)
end

local function rgb_to_hsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local h, s, l = 0, 0, (max + min) / 2
  if max ~= min then
    local d = max - min
    s = l > 0.5 and d / (2 - max - min) or d / (max + min)
    if max == r then
      h = (g - b) / d + (g < b and 6 or 0)
    elseif max == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h / 6
  end
  return h, s, l
end

local function hsl_to_rgb(h, s, l)
  local function hue2rgb(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  if s == 0 then return l * 255, l * 255, l * 255 end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return math.floor(hue2rgb(p, q, h + 1 / 3) * 255 + 0.5),
      math.floor(hue2rgb(p, q, h) * 255 + 0.5),
      math.floor(hue2rgb(p, q, h - 1 / 3) * 255 + 0.5)
end

-- N-step HSL gradient between two hex colors.
local function gradient(from_hex, to_hex, n)
  local h1, s1, l1 = rgb_to_hsl(hex_to_rgb(from_hex))
  local h2, s2, l2 = rgb_to_hsl(hex_to_rgb(to_hex))
  local out = {}
  for i = 0, n - 1 do
    local t = n == 1 and 0 or i / (n - 1)
    local r, g, b = hsl_to_rgb(h1 + (h2 - h1) * t,
      s1 + (s2 - s1) * t,
      l1 + (l2 - l1) * t)
    out[#out + 1] = string.format('#%02X%02X%02X', r, g, b)
  end
  return out
end

-- blame.nvim forces cursorline on both panes; tree has its own winhl group,
-- so recoloring global CursorLine only affects the blame-driven cursorline.
local function apply_blame_hl()
  vim.api.nvim_set_hl(0, 'CursorLine', { bg = theme.black })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_blame_hl })
apply_blame_hl()

-- Belt-and-suspenders: blame.nvim's restore path is skipped on edge-case exits
-- (`:q` on the blame split, original window closed). Force cursorline off on close.
vim.api.nvim_create_autocmd('User', {
  pattern = 'BlameViewClosed',
  callback = function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype ~= 'NvimTree' then
        vim.wo[win].cursorline = false
      end
    end
  end,
})

-- Override blame.nvim's hash highlighter: built-in `pick_spread_indices` insets both
-- palette ends, so oldest lands on washed-out pink and can fall off to nil/white.
-- This maps oldest -> palette[1], newest -> palette[#palette].
local hl_module = require('blame.highlights')
---@diagnostic disable-next-line: duplicate-set-field
hl_module.create_highlights_per_hash = function(parsed_lines, config)
  local hash_time_map = {}
  for _, value in ipairs(parsed_lines) do
    if not hash_time_map[value.hash] then
      hash_time_map[value.hash] = value.author_time or 0
    end
  end
  local sorted_hashes = {}
  for hash, _ in pairs(hash_time_map) do
    sorted_hashes[#sorted_hashes + 1] = hash
  end
  table.sort(sorted_hashes, function(a, b)
    return hash_time_map[a] < hash_time_map[b]
  end)

  local palette = config.colors or {}
  local n_colors = #palette
  local n_commits = #sorted_hashes
  for i, full_hash in ipairs(sorted_hashes) do
    local short = string.sub(full_hash, 1, 7)
    local color
    if n_colors > 0 then
      local idx
      if n_commits == 1 then
        idx = math.ceil(n_colors / 2)
      else
        idx = math.floor((n_colors - 1) * (i - 1) / (n_commits - 1) + 0.5) + 1
      end
      color = palette[math.max(1, math.min(n_colors, idx))]
    end
    vim.api.nvim_set_hl(0, short, { fg = color, ctermfg = math.random(0, 255) })
  end
end

require('blame').setup({
  date_format = '%Y-%m-%d',
  merge_consecutive = false,
  max_summary_width = 30,
  -- Heat-map: index 0 = oldest, last = newest (blame.nvim convention).
  colors = gradient(theme.red, theme.green, 20),
  blame_options = nil,
  commit_detail_view = 'vsplit',
  mappings = {
    commit_info = 'i',
    stack_push  = '<TAB>',
    stack_pop   = '<BS>',
    show_commit = '<CR>',
    close       = { '<Esc>', 'q' },
  },
})

-- Pin `&scroll` so both panes step by the same buffer-line count regardless of height.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'blame',
  callback = function()
    -- Defer: blame.nvim sets `scrollbind` on the editor AFTER FileType fires.
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.wo[win].scrollbind then
          vim.wo[win].scroll = 25
        end
      end
    end)
  end,
})

-- Suppress LSP codelens while blame is open. Core bug #29751: scrollbind
-- compares toplines but <C-d> accounts for virt_lines filler, so the panes
-- drift by ~1 line per codelens. Clearing codelens keeps them in lockstep.
local blame_aug = vim.api.nvim_create_augroup('BlameCodelensSuppress', { clear = true })
vim.api.nvim_create_autocmd('User', {
  group = blame_aug,
  pattern = 'BlameViewOpened',
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= 'blame' then
        pcall(vim.lsp.codelens.enable, false, { bufnr = buf })
      end
    end
  end,
})
vim.api.nvim_create_autocmd('BufWipeout', {
  group = blame_aug,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= 'blame' then return end
    vim.schedule(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= 'blame' then
          pcall(vim.lsp.codelens.enable, true, { bufnr = buf })
        end
      end
    end)
  end,
})
