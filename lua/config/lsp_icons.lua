-- LSP kind icons (Codicons range, guaranteed in any Nerd Font v2.3+).
-- Used by both nvim-cmp (via formatting.format) and Telescope (via
-- protocol.SymbolKind patch + symbol_highlights mapping).

local M = {}

M.icons = {
  Text          = "\u{f027f}  ", -- 󰉿
  Method        = "\u{f01a7}  ", -- 󰆧
  Function      = "\u{f0295}  ", -- 󰊕
  Constructor   = "\u{eb65}  ",  -- 
  Field         = "\u{eb5f}  ",  -- 
  Variable      = "\u{f002b}  ", -- 󰀫
  Class         = "\u{f0831}  ", -- 󰠱
  Interface     = "\u{eb61}  ",  -- 
  Module        = "\u{ea8b}  ",  -- 
  Property      = "\u{f0722}  ", -- 󰜢
  Unit          = "\u{f046d}  ", -- 󰑭
  Value         = "\u{eb5d}  ",  -- 
  Enum          = "\u{ea95}  ",  -- 
  Keyword       = "\u{f030b}  ", -- 󰌋
  Snippet       = "\u{f0336} ",  -- 󰌶
  Color         = "\u{f03d8}  ", -- 󰏘
  File          = "\u{f0219}  ", -- 󰈙
  Reference     = "\u{f0207}  ", -- 󰈇
  Folder        = "\u{ea83}  ",  -- 
  EnumMember    = "\u{eb5e}  ",  -- 
  Constant      = "\u{f03ff}  ", -- 󰏿
  Struct        = "\u{ea91}  ",  -- 
  Event         = "\u{ea86}  ",  -- 
  Operator      = "\u{eb64}  ",  -- 
  TypeParameter = "\u{ea92}  ",  -- 
  Namespace     = "\u{f0317}  ", -- 󰌗
  Package       = "\u{eb29}  ",  -- 
  String        = "\u{f002c}  ", -- 󰀬
  Number        = "\u{f03a0}  ", -- 󰎠
  Boolean       = "\u{ea8f}  ",  -- 
  Array         = "\u{f016a}  ", -- 󰅪
  Object        = "\u{eb63}  ",  -- 
  Key           = "\u{eb11}  ",  -- 
  Null          = "\u{f07e2}  ", -- 󰟢
}

-- Patch protocol.SymbolKind: Telescope reads kind name from this table when
-- rendering the symbol type column, so prefixing here gives us icons.
-- (nvim-cmp has its own cmp.lsp copy and is handled via formatting.format.)
for name, icon in pairs(M.icons) do
  local id = vim.lsp.protocol.SymbolKind[name]
  if type(id) == 'number' then
    vim.lsp.protocol.SymbolKind[id] = icon .. name
  end
end

-- Build a symbol_highlights map for Telescope's lsp_document_symbols picker.
-- Telescope's default map keys by `Method`, `Class`, etc.; since we patched
-- those to `<icon> Method`, the default lookup misses. Re-add the same
-- TelescopeResults* highlights under the prefixed keys.
function M.symbol_highlights()
  local base = {
    Class    = 'TelescopeResultsClass',
    Constant = 'TelescopeResultsConstant',
    Field    = 'TelescopeResultsField',
    Function = 'TelescopeResultsFunction',
    Method   = 'TelescopeResultsMethod',
    Property = 'TelescopeResultsOperator',
    Struct   = 'TelescopeResultsStruct',
    Variable = 'TelescopeResultsVariable',
  }
  local out = {}
  for name, hl in pairs(base) do
    out[(M.icons[name] or '') .. name] = hl
  end
  return out
end

return M
