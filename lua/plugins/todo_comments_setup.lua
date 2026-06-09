-- todo-comments: override tag colors from the theme palette; icons/alts merge
-- from defaults (merge_keywords). Color as a hex string is used verbatim.
local palette = require('config.theme_colors')

require('todo-comments').setup({
  keywords = {
    TODO = { color = palette.pink },
    NOTE = { color = palette.yellow },
    TEST = { color = palette.green },
    PERF = { color = palette.purple },
  },
})
