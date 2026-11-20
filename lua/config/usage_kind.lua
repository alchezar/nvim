-- Heuristic read/write classification for LSP reference usages.
--
-- `textDocument/references` carries no access kind, so we infer it from the
-- Treesitter node sitting at each usage position:
--   * LHS of `=` / compound-assign (`+=`, ...) -> write
--   * `&mut x`                                  -> write
--   * `++` / `--`                               -> write
--   * struct-literal field (`Foo { x: v }` / shorthand `Foo { x }`) -> write
--   * field/element access (`a.b = x`, `a[i] = x`) reads the *container* `a`
--     and the index `i`, a value that builds the target (`&mut P::new(x)`) too
--   * everything else                           -> read
--
-- This is type-blind on purpose: mutation through a method (`vec.push(x)`) takes
-- `&mut self` invisibly and is reported as a read. That gap is the price of not
-- round-tripping the language server; `documentHighlight` would be needed for it.

local M = {}

-- Assignment-like nodes -> the field holding the write target.
local ASSIGN_TARGET = {
  assignment_expression           = 'left', -- rust, c, js/ts
  compound_assignment_expr        = 'left', -- rust
  augmented_assignment_expression = 'left', -- js/ts
  augmented_assignment            = 'left', -- python
  assignment                      = 'left', -- python, generic fallback
}

-- Postfix/prefix mutation (`x++`, `--x`) in C/JS-family grammars.
local UPDATE = {
  update_expression = true,
}

-- Parents through which a usage still names the place being accessed, like
-- the field side of an access or a deref. The value is the slot that keeps
-- the place, `true` for any.
local PLACE = {
  field_expression   = 'field',     -- rust, c
  member_expression  = 'property',  -- js/ts
  attribute          = 'attribute', -- python
  scoped_identifier  = 'name',      -- rust `m::X`
  pointer_expression = true,        -- c `*p`
}

-- Destructuring targets (`(a, b) = ...`, `S { n: a } = ...`) and their parts.
-- They keep the place for an assignment only, as anywhere else such a list
-- builds a temporary out of reads.
local PATTERN = {
  tuple_expression          = true, -- rust
  array_expression          = true,
  struct_expression         = 'body',
  field_initializer_list    = true,
  field_initializer         = 'value',
  call_expression           = 'arguments', -- tuple struct `S(a, b) = ...`
  arguments                 = true,
  array_pattern             = true,        -- js/ts
  object_pattern            = true,
  pair_pattern              = 'value',
  rest_pattern              = true,
  assignment_pattern        = 'left',
  object_assignment_pattern = 'left',
  pattern_list              = true, -- python
  tuple_pattern             = true,
  list_pattern              = true,
  list_splat_pattern        = true,
}

-- Field of `parent` that `child` sits in, or nil.
local function slot(parent, child)
  for c, field in parent:iter_children() do
    if c:id() == child:id() then return field end
  end
end

-- Does `set` list `parent` as keeping its child in slot `at`?
local function keeps(set, parent, at)
  local keep = set[parent:type()]
  return keep == true or (keep ~= nil and keep == at)
end

-- Of the rust unary operators only a deref `*p` names a place.
local function is_deref(node)
  return node:type() == 'unary_expression' and node:child(0):type() == '*'
end

-- Walk up from the usage node while it names the accessed place or a part of
-- a destructuring target, deciding at the first node that uses it.
local function classify_node(node)
  local cur, destructured = node, false
  while true do
    local parent = cur:parent()
    if not parent then return 'read' end
    local ptype, at = parent:type(), slot(parent, cur)

    local target = ASSIGN_TARGET[ptype]
    if target then return at == target and 'write' or 'read' end

    -- Struct/record literal: `Foo { name: value }` writes the field `name`.
    if ptype == 'field_initializer' and at == 'field' then return 'write' end

    -- Shorthand `Foo { name }`: also initializes the field `name`.
    if ptype == 'shorthand_field_initializer' then return 'write' end

    -- Past a destructuring list the usage is part of a temporary, which `++`,
    -- `&mut` or an access only read.
    if UPDATE[ptype] then return destructured and 'read' or 'write' end

    -- Rust `&mut x` mutable borrow; a shared `&x` only reads.
    if ptype == 'reference_expression' then
      if destructured then return 'read' end
      for child in parent:iter_children() do
        if child:type() == 'mutable_specifier' then return 'write' end
      end
      return 'read'
    end

    if keeps(PATTERN, parent, at) then
      destructured = true
    elseif ptype ~= 'parenthesized_expression' then
      if destructured or not (keeps(PLACE, parent, at) or is_deref(parent)) then
        return 'read'
      end
    end
    cur = parent
  end
end

-- Returns 'read' | 'write' | nil (nil = couldn't parse / no node).
function M.classify(filename, lnum, col)
  if not filename or filename == '' then return nil end
  local bufnr = vim.fn.bufadd(filename)
  if bufnr == 0 then return nil end
  vim.fn.bufload(bufnr)

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return nil end
  pcall(function() parser:parse() end)

  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { lnum - 1, col - 1 } })
  if not node then return nil end

  local kok, kind = pcall(classify_node, node)
  return kok and kind or nil
end

return M
