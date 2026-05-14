-- blame.nvim: side-panel git blame with date heat-map.
-- Older commits are red, newer commits are green (smooth HSL gradient).
-- Open via <leader>gb (mapped in keys.lua, replaces :Gitsigns blame).

local theme = require('theme_colors')

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
