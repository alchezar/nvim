-- plpgsql_highlight paints $$ bodies the sql grammar cannot parse; the group
-- each word ends up with is what the reader sees.
local H = require('tests.helpers')
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = H.new_child()

local T = new_set({ hooks = { post_once = child.stop } })

local FUNC = {
  'SELECT 1;',
  'CREATE FUNCTION add_tag(p_tag TEXT) RETURNS void AS $$',
  'DECLARE n INT := 0;',
  'BEGIN',
  "  FOREACH x IN ARRAY tags LOOP n := n + 1; END LOOP;",
  "  RAISE NOTICE 'tag %', p_tag;",
  '  PERFORM notify_all(p_tag);',
  'END;',
  '$$ LANGUAGE plpgsql;',
}

-- Group of each { row, word } (1-based) from the module's marks.
local function groups(lines, words)
  child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  child.cmd('setlocal filetype=sql')
  return child.lua([[
    local words = ...
    local ns = vim.api.nvim_get_namespaces().plpgsql_lexical
    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    local out = {}
    for _, w in ipairs(words) do
      local row, word = w[1], w[2]
      local col = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]:find(word, 1, true) - 1
      out[#out + 1] = word .. '=-'
      for _, m in ipairs(marks) do
        if m[2] == row - 1 and m[3] == col then out[#out] = word .. '=' .. m[4].hl_group end
      end
    end
    return out
  ]], { words })
end

local WORDS = {
  { 1, 'SELECT' }, { 2, '$$' }, { 5, 'FOREACH' }, { 5, 'tags' }, { 6, "'tag %'" },
  { 6, 'p_tag' }, { 7, 'notify_all' }, { 3, 'INT' },
}

local WANT = {
  'SELECT=-', '$$=PlpgsqlDelim', 'FOREACH=@keyword', 'tags=PlpgsqlVariable',
  "'tag %'=@string", 'p_tag=PlpgsqlParam', 'notify_all=@function.call', 'INT=PlpgsqlType',
}

T['paints body tokens, leaves SQL outside alone'] = function()
  child.setup({ treesitter = true })
  child.lua([[require('plugins.plpgsql_highlight')]])
  eq(groups(FUNC, WORDS), WANT)
end

-- 6fb2b62: since 0.12 a missing sql parser is nil, not an error, and the
-- FileType handler crashed. The body is still painted, minus parameters.
T['works without the sql parser'] = function()
  child.setup()
  child.lua([[require('plugins.plpgsql_highlight')]])
  local got = groups(FUNC, { { 2, '$$' }, { 5, 'FOREACH' }, { 6, 'p_tag' } })
  eq(got, { '$$=PlpgsqlDelim', 'FOREACH=@keyword', 'p_tag=PlpgsqlVariable' })
  eq(child.v.errmsg, '')
end

return T
