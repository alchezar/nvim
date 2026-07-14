-- Treat scaffolding suffixes as the base filetype
-- (nginx.conf.template -> nginx, config.toml.example -> toml).
local function match_without_suffix(suffix)
  return function(path)
    return vim.filetype.match({ filename = (path:gsub('%.' .. suffix .. '$', '')) })
  end
end

vim.filetype.add({
  pattern = {
    ['.*%.template'] = match_without_suffix('template'),
    ['.*%.example'] = match_without_suffix('example'),
  },
})
