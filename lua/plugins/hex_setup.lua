-- hex.nvim: open binaries in xxd view.
-- Defaults flag any non-utf-8 file as binary (catches .zsh_history etc.);
-- pre-read uses an extension list + magic-byte sniff, post-read disabled.

local binary_ext = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'tiff', 'heic',
  'out', 'bin', 'exe', 'dll', 'so', 'dylib', 'o', 'a',
}

local exe_magic = {
  '\x7f\x45\x4c\x46', -- ELF (Linux)
  '\xfe\xed\xfa\xce', -- Mach-O 32 BE
  '\xfe\xed\xfa\xcf', -- Mach-O 64 BE
  '\xce\xfa\xed\xfe', -- Mach-O 32 LE
  '\xcf\xfa\xed\xfe', -- Mach-O 64 LE
  '\xca\xfe\xba\xbe', -- Mach-O universal
}

local function is_binary_pre_read()
  if vim.bo.ft ~= '' then return false end
  if vim.bo.bin then return true end

  local ext = vim.fn.expand('%:e'):lower()
  if vim.tbl_contains(binary_ext, ext) then return true end

  -- Extensionless files: peek at magic bytes (dotfiles like .zshrc have ext='zshrc' in vim).
  if ext == '' then
    local f = io.open(vim.fn.expand('%:p'), 'rb')
    if not f then return false end
    local head = f:read(4) or ''
    f:close()
    for _, sig in ipairs(exe_magic) do
      if head == sig then return true end
    end
    if head:sub(1, 2) == 'MZ' then return true end
  end
  return false
end

require('hex').setup({
  is_file_binary_pre_read  = is_binary_pre_read,
  is_file_binary_post_read = function() return false end,
})
