-- Shared color palette used by `colors/kinder_theme.lua` and other configs.
-- Split into `editor` (neutral UI tones), `syntax` (accent colors) and `diff`
-- (muted backgrounds for diffs). The metatable below keeps flat access
-- (`palette.red`, `palette.bg`) working so existing consumers need no changes;
-- `diff` is accessed nested (`palette.diff.add`).
local editor = {
  bg     = "#262626",
  fg     = "#DCDCDC",
  white  = "#F7F1FF",
  gray   = "#ABB2BF",
  silver = "#797979",
  dark   = "#5A5A5A",
  float  = "#333333",
  black  = "#181818",
  cobalt = "#0055C5"
}

local syntax = {
  brown   = "#9A6A5C",
  pink    = "#FC618D",
  red     = "#FC6161",
  orange  = "#FFA348",
  yellow  = "#FCE566",
  lime    = "#CDEF58",
  green   = "#7BD88F",
  teal    = "#20999D",
  emerald = "#00DCC3",
  cyan    = "#5AD4E6",
  blue    = "#61AFEF",
  purple  = "#948AE3",
}

local diff = {
  add    = "#1f3a2a",
  delete = "#3a1f1f",
  change = "#2a2f3a",
  text   = "#3a3520",
}

return setmetatable({ editor = editor, syntax = syntax, diff = diff }, {
  __index = function(_, key)
    return editor[key] or syntax[key]
  end,
})
