-- Heuristic read/write classification for LSP reference usages.
--
-- `textDocument/references` carries no access kind, so we infer it from the
-- Treesitter node sitting at each usage position:
--   * LHS of `=` / compound-assign (`+=`, ...) -> write
--   * `&mut x`                                  -> write
--   * `++` / `--`                               -> write
--   * struct-literal field (`Foo { x: v }` / shorthand `Foo { x }`) -> write
--   * field/element access (`a.b = x`, `a[i] = x`) reads the *container* `a`
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
  augmented_assignment_expression = 'left', -- python, js/ts
  assignment                      = 'left', -- generic fallback
}

-- Container access: writing `a.b`/`a[i]` still only *reads* `a`.
local CONTAINER = {
  field_expression = true,
  index_expression = true,
}

-- Postfix/prefix mutation (`x++`, `--x`) in C/JS-family grammars.
local UPDATE = {
  update_expression = true,
}

-- Is `inner`'s range fully inside `outer`'s?
local function range_contains(outer, inner)
  local osr, osc, oer, oec = outer:range()
  local isr, isc, ier, iec = inner:range()
  local after_start        = isr > osr or (isr == osr and isc >= osc)
  local before_end         = ier < oer or (ier == oer and iec <= oec)
  return after_start and before_end
end

-- Walk up from the usage node, deciding access kind at the first node that fixes it.
local function classify_node(node)
  local cur = node
  for _ = 1, 6 do
    local parent = cur:parent()
    if not parent then break end
    local ptype = parent:type()

    -- Container access: if `cur` is the object being indexed/dotted, it's a read,
    -- even when the whole access is assigned to.
    if CONTAINER[ptype] then
      local obj = parent:field('value')[1] or parent:named_child(0)
      if obj and obj:id() == cur:id() then return 'read' end
    end

    if UPDATE[ptype] then return 'write' end

    -- Struct/record literal: `Foo { name: value }` writes the field `name`.
    if ptype == 'field_initializer' then
      local fname = parent:field('field')[1]
      if fname and fname:id() == node:id() then return 'write' end
    end

    -- Shorthand `Foo { name }`: also initializes the field `name`.
    if ptype == 'shorthand_field_initializer' then return 'write' end

    local field = ASSIGN_TARGET[ptype]
    if field then
      local target = parent:field(field)[1]
      if target and range_contains(target, node) then return 'write' end
      return 'read' -- sitting on the RHS
    end

    -- Rust `&mut x` mutable borrow.
    if ptype == 'reference_expression' then
      for child in parent:iter_children() do
        if child:type() == 'mutable_specifier' then return 'write' end
      end
    end

    cur = parent
  end
  return 'read'
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
