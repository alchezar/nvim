local cmp = require('cmp')
local luasnip = require('luasnip')
local lsp_icons = require('config.lsp_icons')
local compare = require('cmp.config.compare')
local kinds = require('cmp.types').lsp.CompletionItemKind
local theme = require('config.theme_colors')

-- Teal tint for the origin column (the trait/module a method comes from).
local function set_origin_hl()
  vim.api.nvim_set_hl(0, 'CmpItemMenuOrigin', { fg = theme.teal })
end
set_origin_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_origin_hl })

-- Trim a string to n display chars (multibyte-safe) with an ellipsis.
local function truncate(s, n)
  if not s or s == '' or vim.fn.strchars(s) <= n then return s end
  return vim.fn.strcharpart(s, 0, n - 1) .. '…'
end

cmp.setup({
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  formatting = {
    fields = { 'abbr', 'kind', 'menu' },
    format = function(entry, vim_item)
      local icon = lsp_icons.icons[vim_item.kind] or ''
      vim_item.kind = icon .. vim_item.kind
      local ld = entry:get_completion_item().labelDetails
      -- fullFunctionSignatures gives "pub const fn name(args) -> Ret"; show just
      -- "name(args) -> Ret" as the label. Non-fn items get the type appended.
      if ld and ld.description and ld.description ~= '' then
        local sig = ld.description:match('fn%s+(.+)')
        if sig then
          vim_item.abbr = sig
        else
          vim_item.abbr = vim_item.abbr .. '  ' .. ld.description
        end
      end
      -- Fixed caps so one long signature can't stretch the menu across the screen
      -- and crowd out the docs window (which then overlaps the names).
      vim_item.abbr = truncate(vim_item.abbr, 50)
      -- Menu = origin (trait/module) only, teal; empty for inherent methods.
      local origin = ld and ld.detail and ld.detail:match('^%(') and ld.detail or nil
      if origin then
        vim_item.menu = truncate(origin, 30)
        vim_item.menu_hl_group = 'CmpItemMenuOrigin'
      else
        vim_item.menu = nil
      end
      return vim_item
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.abort(),
    ['<CR>'] = cmp.mapping.confirm({ select = true }),
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item({ behavior = cmp.SelectBehavior.Select }) -- highlight only, no preview insert
      elseif luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
      else
        fallback()
      end
    end, { 'i', 's' }),
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select }) -- highlight only, no preview insert
      elseif luasnip.jumpable(-1) then
        luasnip.jump(-1)
      else
        fallback()
      end
    end, { 'i', 's' }),
  }),
  window = {
    completion = cmp.config.window.bordered(),
    documentation = cmp.config.window.bordered({
      max_width = math.min(80, math.floor(vim.o.columns * 0.4)),
      max_height = math.floor(vim.o.lines * 0.4),
    }),
  },
  sorting = {
    comparators = {
      -- Snippets always sort last, below LSP methods/variables.
      function(a, b)
        local a_snip = a:get_kind() == kinds.Snippet
        local b_snip = b:get_kind() == kinds.Snippet
        if a_snip ~= b_snip then return not a_snip end
      end,
      compare.offset,
      compare.exact,
      compare.score,
      compare.recently_used,
      compare.locality,
      compare.kind,
      compare.sort_text,
      compare.length,
      compare.order,
    },
  },
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
    { name = 'nvim_lsp_signature_help' },
    { name = 'luasnip' },
  }, {
    { name = 'buffer' },
    { name = 'path' },
  }),
})

-- Cmdline completion: `/` and `?` search use buffer words, `:` uses cmdline + path.
cmp.setup.cmdline({ '/', '?' }, {
  mapping = cmp.mapping.preset.cmdline(),
  sources = { { name = 'buffer' } },
})

cmp.setup.cmdline(':', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = cmp.config.sources({
    { name = 'path' },
  }, {
    { name = 'cmdline' },
  }),
  matching = { disallow_symbol_nonprefix_matching = false },
})

-- Split a parameter list on top-level commas (commas inside <>, (), [] are kept).
local function split_params(s)
  local parts, depth, buf = {}, 0, ''
  for i = 1, #s do
    local c = s:sub(i, i)
    if c:match('[(<%[]') then depth = depth + 1 elseif c:match('[)>%]]') then depth = depth - 1 end
    if c == ',' and depth == 0 then
      parts[#parts + 1] = vim.trim(buf); buf = ''
    else
      buf = buf .. c
    end
  end
  if vim.trim(buf) ~= '' then parts[#parts + 1] = vim.trim(buf) end
  return parts
end

-- Put each function parameter on its own line. Returns a list of lines.
local function reflow_signature(line)
  local open = line:find('%(')
  if not open then return { line } end
  local depth, close = 0, nil
  for i = open, #line do
    local c = line:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
      if depth == 0 then
        close = i; break
      end
    end
  end
  if not close then return { line } end
  local params = split_params(line:sub(open + 1, close - 1))
  if #params < 2 then return { line } end
  local out = { line:sub(1, open) }
  for _, p in ipairs(params) do out[#out + 1] = '    ' .. p .. ',' end
  out[#out + 1] = line:sub(close)
  return out
end

-- Render docs like LSP hover: keep raw markdown (treesitter + markview) instead of
-- cmp's stylize_markdown, and reflow long signatures one param per line.
local docs_view = require('cmp.view.docs_view')
local orig_open = docs_view.open
docs_view.open = function(self, e, view, bottom_up)
  local orig_stylize = vim.lsp.util.stylize_markdown
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.util.stylize_markdown = function(buf, contents)
    local lines = {}
    for _, l in ipairs(vim.split(table.concat(contents, '\n'), '\n')) do
      if l:match('fn%s*[%w_]*%s*%(') and l:find(',') then
        vim.list_extend(lines, reflow_signature(l))
      else
        lines[#lines + 1] = l
      end
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if vim.bo[buf].filetype ~= 'markdown' then vim.bo[buf].filetype = 'markdown' end
    return lines
  end
  local ok, err = pcall(orig_open, self, e, view, bottom_up)
  vim.lsp.util.stylize_markdown = orig_stylize
  if not ok then error(err) end
end
