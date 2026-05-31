-- Shared color palette used by `colors/kinder_theme.lua` and other configs.
-- Split into `editor` (neutral UI tones) and `syntax` (accent colors). The
-- metatable below keeps flat access (`palette.red`, `palette.bg`) working so
-- existing consumers need no changes.
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

return setmetatable({ editor = editor, syntax = syntax }, {
  __index = function(_, key)
    return editor[key] or syntax[key]
  end,
})
