-- Treat *.xxx.template as filetype xxx (e.g. nginx.conf.template -> nginx).
vim.filetype.add({
  pattern = {
    ['.*%.template'] = function(path)
      return vim.filetype.match({ filename = (path:gsub('%.template$', '')) })
    end,
  },
})
