-- Heading tree of a markdown buffer, for the <leader>o picker: ATX headings
-- (#..######) flattened back into display order with tree-branch prefixes.

local M = {}

-- Strip inline markup so the outline reads as plain text: links keep their
-- label, emphasis/code markers and a closing `###` run drop out.
local function plain(text)
  text = text:gsub('%[([^%]]*)%]%b()', '%1'):gsub('[*`~]', '')
  return vim.trim((text:gsub('%s+#+%s*$', '')))
end

-- Headings outside fenced code blocks and YAML front matter, where a `#` is a
-- comment rather than a heading.
local function collect(bufnr)
  local out, fence, front = {}, nil, nil
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local ticks = line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
    if lnum == 1 and line:match('^%-%-%-%s*$') then
      front = true
    elseif front then
      if line:match('^%-%-%-%s*$') or line:match('^%.%.%.%s*$') then front = nil end
    elseif fence then
      if ticks and ticks:sub(1, 1) == fence:sub(1, 1) and #ticks >= #fence then fence = nil end
    elseif ticks then
      fence = ticks
    else
      local hashes, text = line:match('^(#+)%s+(.+)$')
      if hashes and #hashes <= 6 then
        out[#out + 1] = { lnum = lnum, level = #hashes, text = plain(text) }
      end
    end
  end
  return out
end

-- Levels may skip (# then ###), so nesting follows the stack, not the raw level.
local function build_tree(items)
  local root = { children = {} }
  local stack = { { node = root, level = 0 } }
  for _, item in ipairs(items) do
    while #stack > 1 and stack[#stack].level >= item.level do table.remove(stack) end
    local parent = stack[#stack].node
    local node = { lnum = item.lnum, level = item.level, text = item.text, children = {} }
    parent.children[#parent.children + 1] = node
    stack[#stack + 1] = { node = node, level = item.level }
  end
  return root
end

-- Flat list in document order: { lnum, level, text, indent } - indent is the
-- nesting depth, so the picker only has to pad and color the text.
function M.headings(bufnr)
  local out = {}
  local function walk(node, depth)
    for _, child in ipairs(node.children) do
      out[#out + 1] = { lnum = child.lnum, level = child.level, text = child.text, indent = depth }
      walk(child, depth + 1)
    end
  end
  walk(build_tree(collect(bufnr)), 0)
  return out
end

return M
