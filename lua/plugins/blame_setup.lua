-- blame.nvim: side-panel git blame with date heat-map.
-- Older commits are red, newer commits are green (smooth HSL gradient).
-- Open via <leader>gb (mapped in keys.lua, replaces :Gitsigns blame).

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
         math.floor(hue2rgb(p, q, h)         * 255 + 0.5),
         math.floor(hue2rgb(p, q, h - 1 / 3) * 255 + 0.5)
end

-- Build N-step HSL gradient between two hex colors (oldest -> newest).
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

-- blame.nvim forces `cursorline = true` on both its panel and the synced
-- editor window. Since cursorline is otherwise unused outside the tree
-- (which has its own winhl-mapped `NvimTreeCursorLine`), recoloring the
-- global `CursorLine` group affects only the blame-driven cursorline.
local function apply_blame_hl()
  vim.api.nvim_set_hl(0, 'CursorLine', { bg = theme.black })
end
vim.api.nvim_create_autocmd('ColorScheme', { callback = apply_blame_hl })
apply_blame_hl()

-- blame.nvim tries to restore the editor window's original options on close,
-- but that path is skipped when the user quits blame in unusual ways (e.g.
-- `:q` on the blame split, original window already closed). Belt-and-suspenders:
-- on `BlameViewClosed`, force `cursorline = false` on every regular window,
-- leaving NvimTree alone since it owns its own cursorline.
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

-- Override blame.nvim's hash highlighter: its built-in `pick_spread_indices`
-- insets both ends of the palette, so the oldest commit lands on index ~4
-- (washed-out pink that reads as white on a dim background) and, when there
-- are more than 2*N+1 unique commits, index 0 -> nil fg -> literal white.
-- This version maps oldest -> palette[1] and newest -> palette[#palette].
local hl_module = require('blame.highlights')
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
  -- Heat-map: index 0 = oldest, last index = newest (blame.nvim convention).
  -- Smooth 20-step HSL gradient red -> yellow -> green.
  colors = gradient(theme.red, theme.green, 20),
  blame_options = nil,  -- pass extra `git blame` flags here if needed
  commit_detail_view = 'vsplit',
  format_fn = nil,
  mappings = {
    commit_info = 'i',
    stack_push  = '<TAB>',
    stack_pop   = '<BS>',
    show_commit = '<CR>',
    close       = { '<Esc>', 'q' },
  },
})

-- Pin `&scroll` (step for <C-d>/<C-u>) so both windows jump by the same
-- buffer-line count regardless of effective height differences.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'blame',
  callback = function()
    -- Deferred: blame.nvim sets `scrollbind` on the editor window AFTER the
    -- FileType event fires, so the editor wouldn't be detectable yet.
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.wo[win].scrollbind then
          vim.wo[win].scroll = 25
        end
      end
    end)
  end,
})

-- Suppress LSP code-lens virtual lines on the bound editor buffer while
-- blame is open. Neovim core bug (issue #29751): native `scrollbind`
-- compares buffer toplines, but `<C-d>` accounts for `virt_lines` filler
-- on the active side - the blame side has none, so the two windows drift
-- by ~1 buffer line per code-lens passed. PR #29766 mitigated this for
-- some paths, but in nvim 0.12 LSP codelens renders as `virt_lines` and
-- the drift returns. Clearing codelens for the duration of the blame
-- session keeps both sides in lockstep.
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
