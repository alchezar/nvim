-- Bridge every LSP's work-done progress into Neovide's native progress bar (top strip).
-- Neovide draws any 'progress' message; nvim_echo(kind='progress') is what emits one.
-- The cmdline shows "<client>: <pct>% <title> <message>", mirroring what fidget did.
if not vim.g.neovide then return end

-- key -> { pct = number|false, client, title, message }; false pct == indeterminate.
local active = {}
-- Nudged forward on each indeterminate update so the bar visibly lives while work runs.
local indet = 0

local function show(entry)
  local text = entry.title or ''
  if entry.message and entry.message ~= '' then
    text = text ~= '' and (text .. ' ' .. entry.message) or entry.message
  end
  local pct = entry.pct
  if type(pct) ~= 'number' then
    indet = math.min(indet + 15, 85)
    pct = indet
  end
  -- history=false keeps these out of :messages; id makes it one updating bar.
  pcall(vim.api.nvim_echo, { { text } }, false,
    { kind = 'progress', source = 'lsp', id = 'lsp', title = entry.client, status = 'running', percent = pct })
end

local function done()
  indet = 0
  pcall(vim.api.nvim_echo, { { '' } }, false,
    { kind = 'progress', source = 'lsp', id = 'lsp', title = '', status = 'success', percent = 100 })
end

vim.api.nvim_create_autocmd('LspProgress', {
  callback = function(ev)
    local params = ev.data.params
    local val = params and params.value
    if not val or not val.kind then return end
    local key = ev.data.client_id .. '/' .. tostring(params.token)
    if val.kind == 'end' then
      active[key] = nil
      local nxt = next(active)
      if nxt then show(active[nxt]) else done() end
    else
      local prev = active[key] or {}
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      active[key] = {
        pct = val.percentage or false,
        client = client and client.name or 'LSP',
        title = val.title or prev.title, -- title arrives only in 'begin'
        message = val.message,
      }
      show(active[key])
    end
  end,
})
