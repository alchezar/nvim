-- Set the name of the theme
vim.g.colors_name = "kinder_theme"
vim.o.background = 'dark'

-- Clear existing highlights
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end

-- Color palette is shared with other configs (see lua/theme_colors.lua)
local colors = require('theme_colors')

local function highlight(group, color)
	local style = color.style and 'gui=' .. color.style or 'gui=NONE'
	local fg = color.fg and 'guifg=' .. color.fg or 'guifg=NONE'
	local bg = color.bg and 'guibg=' .. color.bg or 'guibg=NONE'
	vim.cmd('highlight ' .. group .. ' ' .. style .. ' ' .. fg .. ' ' .. bg)
end

-- Base color for the status line
vim.api.nvim_set_hl(0, 'StatusLine', {fg = colors.fg, bg = colors.bg})
vim.api.nvim_set_hl(0, 'CommandLine', {fg = colors.fg, bg = colors.bg})

-- Set background color to transparent
vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })

-- Visual selection background
vim.api.nvim_set_hl(0, "Visual", { bg = "#0055C5" })

-- Default highlights. Use ":Inspect" command to find correct type.
vim.api.nvim_set_hl(0, "Whitespace", { fg = colors.silver })
vim.api.nvim_set_hl(0, "Constructor", { fg = colors.red })
vim.api.nvim_set_hl(0, "Special", { fg = colors.red })
vim.api.nvim_set_hl(0, "Keyword", { fg = colors.red })
vim.api.nvim_set_hl(0, "Noise", { fg = colors.red })
vim.api.nvim_set_hl(0, "Operator", { fg = colors.red })
vim.api.nvim_set_hl(0, "Statement", { fg = colors.red })
vim.api.nvim_set_hl(0, "Function", { fg = colors.green })
vim.api.nvim_set_hl(0, "Function.call", { fg = colors.green })
vim.api.nvim_set_hl(0, "Function.method.call", { fg = colors.green })
vim.api.nvim_set_hl(0, "String", { fg = colors.yellow })
vim.api.nvim_set_hl(0, "Number", { fg = colors.purple })
vim.api.nvim_set_hl(0, "Constant", { fg = colors.purple })
vim.api.nvim_set_hl(0, "Variable", { fg = colors.white })
vim.api.nvim_set_hl(0, "Variable.member", { fg = colors.gray })
vim.api.nvim_set_hl(0, "Punctuation.bracket", { fg = colors.gray })
vim.api.nvim_set_hl(0, "Delimiter", { fg = colors.gray })
vim.api.nvim_set_hl(0, "Quote", { fg = colors.gray })
vim.api.nvim_set_hl(0, "Identifier", { fg = colors.gray })
vim.api.nvim_set_hl(0, "Comment", { fg = colors.silver })
vim.api.nvim_set_hl(0, "WinSeparator", { fg = colors.dark })
vim.api.nvim_set_hl(0, "VirtColumn", { fg = colors.dark })
vim.api.nvim_set_hl(0, "FloatBorder", { fg = colors.dark })
vim.api.nvim_set_hl(0, "FloatTitle", { fg = colors.dark })
vim.api.nvim_set_hl(0, "LspHoverSeparator", { fg = colors.dark })
vim.api.nvim_set_hl(0, "@punctuation.special", { fg = colors.dark })

-- C / C++ highlights (Treesitter + LSP semantic tokens from clangd)
local function cpp_treesitter_highlights(lang)
	return {
		["@keyword." .. lang]                  = { fg = colors.red },
		["@keyword.return." .. lang]           = { fg = colors.red },
		["@keyword.operator." .. lang]         = { fg = colors.red },
		["@keyword.modifier." .. lang]         = { fg = colors.red },
		["@keyword.conditional." .. lang]      = { fg = colors.red },
		["@keyword.repeat." .. lang]           = { fg = colors.red },
		["@keyword.import." .. lang]           = { fg = colors.red },
		["@keyword.directive." .. lang]        = { fg = colors.red },
		["@keyword.directive.define." .. lang] = { fg = colors.red },
		["@function." .. lang]                 = { fg = colors.green },
		["@function.call." .. lang]            = { fg = colors.green },
		["@function.method." .. lang]          = { fg = colors.green },
		["@function.method.call." .. lang]     = { fg = colors.green },
		["@function.builtin." .. lang]         = { fg = colors.green },
		["@constructor." .. lang]              = { fg = colors.green },
		["@type." .. lang]                     = { fg = colors.blue },
		["@type.builtin." .. lang]             = { fg = colors.red },
		["@type.qualifier." .. lang]           = { fg = colors.red },
		["@variable." .. lang]                 = { fg = colors.gray },
		["@variable.parameter." .. lang]       = { fg = colors.orange },
		["@variable.member." .. lang]          = { fg = colors.white },
		["@variable.builtin." .. lang]         = { fg = colors.white },
		["@property." .. lang]                 = { fg = colors.white },
		["@string." .. lang]                   = { fg = colors.yellow },
		["@string.escape." .. lang]            = { fg = colors.purple },
		["@string.special." .. lang]           = { fg = colors.purple },
		["@character." .. lang]                = { fg = colors.yellow },
		["@character.special." .. lang]        = { fg = colors.yellow },
		["@number." .. lang]                   = { fg = colors.purple },
		["@boolean." .. lang]                  = { fg = colors.red },
		["@constant." .. lang]                 = { fg = colors.lime },
		["@constant.builtin." .. lang]         = { fg = colors.red },
		["@constant.macro." .. lang]           = { fg = colors.brown },
		["@operator." .. lang]                 = { fg = colors.red },
		["@punctuation.bracket." .. lang]      = { fg = colors.gray },
		["@punctuation.delimiter." .. lang]    = { fg = colors.gray },
		["@comment." .. lang]                  = { fg = colors.silver },
		["@module." .. lang]                   = { fg = colors.dark },
		["@label." .. lang]                    = { fg = colors.red },
		["@attribute." .. lang]                = { fg = colors.cyan },
		["@preproc." .. lang]                  = { fg = colors.red },
	}
end

local function cpp_lsp_highlights(lang)
	return {
		["@lsp.type.class." .. lang]         = { fg = colors.blue },
		["@lsp.type.struct." .. lang]        = { fg = colors.blue },
		["@lsp.type.enum." .. lang]          = { fg = colors.cyan },
		["@lsp.type.enumMember." .. lang]    = { fg = colors.pink },
		["@lsp.type.interface." .. lang]     = { fg = colors.teal },
		["@lsp.type.concept." .. lang]       = { fg = colors.teal },
		["@lsp.type.type." .. lang]          = { fg = colors.blue },
		["@lsp.type.typeAlias." .. lang]     = { fg = colors.blue },
		["@lsp.type.typeParameter." .. lang] = { fg = colors.teal },
		["@lsp.type.parameter." .. lang]     = { fg = colors.orange },
		["@lsp.type.property." .. lang]      = { fg = colors.white },
		["@lsp.type.method." .. lang]        = { fg = colors.green },
		["@lsp.type.function." .. lang]      = { fg = colors.green },
		["@lsp.type.variable." .. lang]      = { fg = colors.gray },
		["@lsp.type.namespace." .. lang]     = { fg = colors.dark },
		["@lsp.type.macro." .. lang]         = { fg = colors.brown, bold = true },
		["@lsp.type.keyword." .. lang]       = { fg = colors.red },
		["@lsp.type.string." .. lang]        = { fg = colors.yellow },
		["@lsp.type.number." .. lang]        = { fg = colors.purple },
		["@lsp.type.operator." .. lang]      = { fg = colors.red },
		["@lsp.type.comment." .. lang]       = { fg = colors.silver },
		["@lsp.type.bracket." .. lang]       = { fg = colors.gray },
		["@lsp.type.label." .. lang]         = { fg = colors.red },
		["@lsp.type.modifier." .. lang]      = { fg = colors.red },
		["@lsp.type.unknown." .. lang]       = { fg = colors.gray },
		-- Modifiers
		["@lsp.typemod.variable.readonly." .. lang]        = { fg = colors.lime },
		["@lsp.typemod.variable.fileScope." .. lang]       = { fg = colors.gray },
		["@lsp.typemod.variable.globalScope." .. lang]     = { fg = colors.lime },
		["@lsp.typemod.variable.functionScope." .. lang]   = { fg = colors.gray },
		["@lsp.typemod.variable.classScope." .. lang]      = { fg = colors.white },
		["@lsp.typemod.property.classScope." .. lang]      = { fg = colors.white },
		["@lsp.typemod.parameter.functionScope." .. lang]  = { fg = colors.orange },
		["@lsp.typemod.function.defaultLibrary." .. lang]  = { fg = colors.green },
		["@lsp.typemod.method.defaultLibrary." .. lang]    = { fg = colors.green },
		["@lsp.typemod.class.defaultLibrary." .. lang]     = { fg = colors.cyan },
		["@lsp.typemod.namespace.defaultLibrary." .. lang] = { fg = colors.dark },
	}
end

for _, lang in ipairs({ "cpp", "c" }) do
	for group, color in pairs(cpp_treesitter_highlights(lang)) do
		vim.api.nvim_set_hl(0, group, color)
	end
	for group, color in pairs(cpp_lsp_highlights(lang)) do
		vim.api.nvim_set_hl(0, group, color)
	end
end

-- JSON highlights
vim.api.nvim_set_hl(0, "jsonBoolean", { fg = colors.red })
vim.api.nvim_set_hl(0, "jsonEscape", { fg = colors.purple })
vim.api.nvim_set_hl(0, "jsonKeyword", { fg = colors.green })
vim.api.nvim_set_hl(0, "jsonString", { fg = colors.yellow })

-- YALM highlights
vim.api.nvim_set_hl(0, "yamlBool", { fg = colors.red })
vim.api.nvim_set_hl(0, "yamlBlockMappingKey", { fg = colors.green })
vim.api.nvim_set_hl(0, "yamlPlainScalar", { fg = colors.blue })
vim.api.nvim_set_hl(0, "yamlFlowString", { fg = colors.yellow })
vim.api.nvim_set_hl(0, "yamlInteger", { fg = colors.purple })

-- Rust highlights (Treesitter + LSP semantic tokens)
-- Vim regex syntax fallbacks (used when treesitter rust parser unavailable).
local rust_legacy_highlights = {
	rustStorage       = { fg = colors.red },
	rustMacro         = { fg = colors.red },
	rustOperator      = { fg = colors.gray },
	rustMacroVariable = { fg = colors.orange },
	rustEnumVariant   = { fg = colors.pink },
	rustLifetime      = { fg = colors.teal },
	rustAttribute     = { fg = colors.dark },
	rustDerive        = { fg = colors.dark },
	rustFoldBraces    = { fg = colors.gray },
	rustSigil         = { fg = colors.red },
}
for group, color in pairs(rust_legacy_highlights) do
	vim.api.nvim_set_hl(0, group, color)
end

local function rust_treesitter_highlights(lang)
	return {
		["@keyword." .. lang]                = { fg = colors.red },
		["@keyword.storate." .. lang]        = { fg = colors.red },
		["@function." .. lang]               = { fg = colors.green },
		["@function.call." .. lang]          = { fg = colors.green },
		["@macro." .. lang]                  = { fg = colors.brown },
		["@type." .. lang]                   = { fg = colors.blue },
		["@type.builtin." .. lang]           = { fg = colors.cyan },
		["@field." .. lang]                  = { fg = colors.gray },
		["@variable." .. lang]               = { fg = colors.white },
		["@variable.parameter." .. lang]     = { fg = colors.orange },
		["@comment." .. lang]                = { fg = colors.silver },
		["@string." .. lang]                 = { fg = colors.yellow },
		["@number." .. lang]                 = { fg = colors.purple },
		["@operator." .. lang]               = { fg = colors.red },
		["@punctuation.bracket." .. lang]    = { fg = colors.gray },
		["@punctuation.delimiter." .. lang]  = { fg = colors.gray },
		["@attribute." .. lang]              = { fg = colors.cyan },
		["@namespace." .. lang]              = { fg = colors.blue },
		["@constructor." .. lang]            = { fg = colors.green },
	}
end

local function rust_lsp_highlights(lang)
	return {
		["@lsp.type.lifetime." .. lang]                = { fg = colors.teal },
		["@lsp.type.enum." .. lang]                    = { fg = colors.cyan },
		["@lsp.type.enumMember." .. lang]              = { fg = colors.pink },
		["@lsp.type.decorator." .. lang]               = { fg = colors.dark },
		["@lsp.type.attributeBracket." .. lang]        = { fg = colors.dark },
		["@lsp.type.derive." .. lang]                  = { fg = colors.teal },
		["@lsp.type.builtinType." .. lang]             = { fg = colors.red },
		["@lsp.type.struct." .. lang]                  = { fg = colors.blue },
		["@lsp.type.parameter." .. lang]               = { fg = colors.orange },
		["@lsp.type.builtinAttribute." .. lang]        = { fg = colors.dark },
		["@lsp.type.deriveHelper." .. lang]            = { fg = colors.dark },
		["@lsp.mode.attribute." .. lang]               = { fg = colors.dark },
		["@lsp.type.namespace." .. lang]               = { fg = colors.dark },
		["@lsp.type.macro." .. lang]                   = { fg = colors.brown, bold = true },
		["@lsp.type.interface." .. lang]               = { fg = colors.teal },
		["@lsp.type.typeAlias." .. lang]               = { fg = colors.blue },
		["@lsp.type.selfKeyword." .. lang]             = { fg = colors.red },
		["@lsp.type.selfTypeKeyword." .. lang]         = { fg = colors.red },
		["@lsp.type.keyword." .. lang]                 = { fg = colors.red },
		["@lsp.type.static." .. lang]                  = { fg = colors.emerald },
		["@lsp.typemod.static.declaration." .. lang]   = { fg = colors.emerald },
		["@lsp.typemod.function.static." .. lang]      = { fg = colors.emerald },
		["@lsp.type.typeParameter." .. lang]           = { fg = colors.teal },
		["@lsp.type.punctuation." .. lang]             = { fg = colors.gray },
		["@lsp.type.variable." .. lang]                = { fg = colors.gray },
		["@lsp.type.const." .. lang]                   = { fg = colors.lime },
		["@lsp.typemod.variable.declaration." .. lang] = { fg = colors.gray },
		["@lsp.typemod.property.declaration." .. lang] = { fg = colors.white },
	}
end

for _, lang in ipairs({ "rust" }) do
	for group, color in pairs(rust_treesitter_highlights(lang)) do
		vim.api.nvim_set_hl(0, group, color)
	end
end

for _, lang in ipairs({ "rust" }) do
	for group, color in pairs(rust_lsp_highlights(lang)) do
		vim.api.nvim_set_hl(0, group, color)
	end
end

-- TypeScript / JavaScript / TSX highlights (Treesitter + LSP semantic tokens)
local function ts_treesitter_highlights(lang)
	return {
		["@keyword." .. lang]                 = { fg = colors.red },
		["@keyword.import." .. lang]          = { fg = colors.red },
		["@keyword.export." .. lang]          = { fg = colors.red },
		["@keyword.return." .. lang]          = { fg = colors.red },
		["@keyword.operator." .. lang]        = { fg = colors.red },
		["@keyword.function." .. lang]        = { fg = colors.red },
		["@keyword.coroutine." .. lang]       = { fg = colors.red },
		["@keyword.modifier." .. lang]        = { fg = colors.red },
		["@keyword.conditional." .. lang]     = { fg = colors.red },
		["@keyword.repeat." .. lang]          = { fg = colors.red },
		["@function." .. lang]                = { fg = colors.green },
		["@function.call." .. lang]           = { fg = colors.green },
		["@function.method." .. lang]         = { fg = colors.green },
		["@function.method.call." .. lang]    = { fg = colors.green },
		["@function.builtin." .. lang]        = { fg = colors.green },
		["@type." .. lang]                    = { fg = colors.blue },
		["@type.builtin." .. lang]            = { fg = colors.red },
		["@variable." .. lang]                = { fg = colors.gray },
		["@variable.parameter." .. lang]      = { fg = colors.orange },
		["@variable.member." .. lang]         = { fg = colors.white },
		["@variable.builtin." .. lang]        = { fg = colors.white },
		["@property." .. lang]                = { fg = colors.white },
		["@constructor." .. lang]             = { fg = colors.green },
		["@string." .. lang]                  = { fg = colors.yellow },
		["@string.escape." .. lang]           = { fg = colors.purple },
		["@string.special." .. lang]          = { fg = colors.purple },
		["@string.regexp." .. lang]           = { fg = colors.orange },
		["@number." .. lang]                  = { fg = colors.purple },
		["@boolean." .. lang]                 = { fg = colors.purple },
		["@constant." .. lang]                = { fg = colors.lime },
		["@constant.builtin." .. lang]        = { fg = colors.purple },
		["@operator." .. lang]                = { fg = colors.gray },
		["@punctuation.bracket." .. lang]     = { fg = colors.silver },
		["@punctuation.delimiter." .. lang]   = { fg = colors.red },
		["@punctuation.special." .. lang]     = { fg = colors.silver },
		["@comment." .. lang]                 = { fg = colors.silver },
		["@module." .. lang]                  = { fg = colors.silver },
		["@tag." .. lang]                     = { fg = colors.red },
		["@tag.attribute." .. lang]           = { fg = colors.orange },
		["@tag.delimiter." .. lang]           = { fg = colors.gray },
	}
end

local function ts_lsp_highlights(lang)
	return {
		["@lsp.type.class." .. lang]             = { fg = colors.blue },
		["@lsp.type.interface." .. lang]         = { fg = colors.teal },
		["@lsp.type.enum." .. lang]              = { fg = colors.cyan },
		["@lsp.type.enumMember." .. lang]        = { fg = colors.pink },
		["@lsp.type.parameter." .. lang]         = { fg = colors.orange },
		["@lsp.type.property." .. lang]          = { fg = colors.white },
		["@lsp.type.method." .. lang]            = { fg = colors.green },
		["@lsp.type.function." .. lang]          = { fg = colors.green },
		["@lsp.type.variable." .. lang]          = { fg = colors.lime },
		["@lsp.typemod.variable.local." .. lang] = { fg = colors.gray },
		["@lsp.type.namespace." .. lang]         = { fg = colors.cyan },
		["@lsp.type.typeAlias." .. lang]         = { fg = colors.blue },
		["@lsp.type.typeParameter." .. lang]     = { fg = colors.teal },
		["@lsp.type.keyword." .. lang]           = { fg = colors.red },
		["@lsp.type.string." .. lang]            = { fg = colors.yellow },
		["@lsp.type.number." .. lang]            = { fg = colors.purple },
		["@lsp.type.decorator." .. lang]         = { fg = colors.brown },
		["@lsp.type.builtinType." .. lang]       = { fg = colors.red },
		-- Built-in globals carry the defaultLibrary modifier:
		-- built-in classes / converters / global functions -> cyan;
		-- built-in objects (console, Math, JSON, ...) -> lime.
		["@lsp.typemod.class.defaultLibrary." .. lang]     = { fg = colors.cyan },
		["@lsp.typemod.function.defaultLibrary." .. lang]  = { fg = colors.cyan },
		["@lsp.typemod.method.defaultLibrary." .. lang]    = { fg = colors.cyan },
		["@lsp.typemod.variable.defaultLibrary." .. lang]  = { fg = colors.lime },
		["@lsp.typemod.namespace.defaultLibrary." .. lang] = { fg = colors.lime },
	}
end

for _, lang in ipairs({ "typescript", "tsx", "javascript" }) do
	for group, color in pairs(ts_treesitter_highlights(lang)) do
		vim.api.nvim_set_hl(0, group, color)
	end
end

for _, lang in ipairs({ "typescript", "typescriptreact", "javascript", "javascriptreact" }) do
	for group, color in pairs(ts_lsp_highlights(lang)) do
		vim.api.nvim_set_hl(0, group, color)
	end
end

-- SQL highlights (used for sqlx::query! injections and standalone .sql files)
local function sql_treesitter_highlights(lang)
	return {
		["@keyword." .. lang]                 = { fg = colors.red },
		["@keyword.operator." .. lang]        = { fg = colors.red },
		["@keyword.modifier." .. lang]        = { fg = colors.red },
		["@keyword.conditional." .. lang]     = { fg = colors.red },
		["@keyword.repeat." .. lang]          = { fg = colors.red },
		["@type." .. lang]                    = { fg = colors.blue },
		["@type.builtin." .. lang]            = { fg = colors.cyan },
		["@function.call." .. lang]           = { fg = colors.green },
		["@variable." .. lang]                = { fg = colors.white },
		["@variable.member." .. lang]         = { fg = colors.gray },
		["@variable.parameter." .. lang]      = { fg = colors.orange },
		["@string." .. lang]                  = { fg = colors.yellow },
		["@number." .. lang]                  = { fg = colors.purple },
		["@number.float." .. lang]            = { fg = colors.purple },
		["@boolean." .. lang]                 = { fg = colors.purple },
		["@operator." .. lang]                = { fg = colors.red },
		["@punctuation.bracket." .. lang]     = { fg = colors.gray },
		["@punctuation.delimiter." .. lang]   = { fg = colors.gray },
		["@attribute." .. lang]               = { fg = colors.cyan },
		["@comment." .. lang]                 = { fg = colors.silver },
	}
end

for _, lang in ipairs({ "sql" }) do
	for group, color in pairs(sql_treesitter_highlights(lang)) do
		vim.api.nvim_set_hl(0, group, color)
	end
end

-- LSP diagnostics: red errors, orange warnings, green hints
vim.api.nvim_set_hl(0, "DiagnosticError", { fg = colors.red })
vim.api.nvim_set_hl(0, "DiagnosticWarn",  { fg = colors.orange })
vim.api.nvim_set_hl(0, "DiagnosticInfo",  { fg = colors.blue })
vim.api.nvim_set_hl(0, "DiagnosticHint",  { fg = colors.gray })
vim.api.nvim_set_hl(0, "DiagnosticOk",    { fg = colors.green })

-- Telescope borders: match yazi's darkgray
vim.api.nvim_set_hl(0, "TelescopeBorder",        { fg = colors.dark })
vim.api.nvim_set_hl(0, "TelescopePromptBorder",  { fg = colors.dark })
vim.api.nvim_set_hl(0, "TelescopeResultsBorder", { fg = colors.dark })
vim.api.nvim_set_hl(0, "TelescopePreviewBorder", { fg = colors.dark })

-- nvim-tree folder colors: blue icons, gray names
vim.api.nvim_set_hl(0, "NvimTreeFolderName",       { fg = colors.gray })
vim.api.nvim_set_hl(0, "NvimTreeOpenedFolderName", { fg = colors.gray, bold = true })
vim.api.nvim_set_hl(0, "NvimTreeEmptyFolderName",  { fg = colors.gray })
vim.api.nvim_set_hl(0, "NvimTreeFolderIcon",       { fg = colors.blue })
vim.api.nvim_set_hl(0, "NvimTreeRootFolder",       { fg = colors.blue, bold = true })

-- nvim-tree git status colors on file names
vim.api.nvim_set_hl(0, "NvimTreeGitFileDirtyHL",   { fg = colors.cyan })  -- modified, unstaged
vim.api.nvim_set_hl(0, "NvimTreeGitFileNewHL",     { fg = colors.red })   -- untracked
vim.api.nvim_set_hl(0, "NvimTreeGitFileStagedHL",  { fg = colors.blue })  -- modified, staged
vim.api.nvim_set_hl(0, "NvimTreeGitFolderDirtyHL",  { fg = colors.cyan })
vim.api.nvim_set_hl(0, "NvimTreeGitFolderNewHL",    { fg = colors.red })
vim.api.nvim_set_hl(0, "NvimTreeGitFolderStagedHL", { fg = colors.blue })

-- gitsigns: sign-column colors (also reused by nvim-scrollbar on the right edge)
vim.api.nvim_set_hl(0, "GitSignsAdd",    { fg = colors.green })
vim.api.nvim_set_hl(0, "GitSignsChange", { fg = colors.blue })
vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = colors.red })

-- ANSI palette for built-in :terminal (used by yazi-in-nvim, etc.)
vim.g.terminal_color_0  = colors.bg       -- black
vim.g.terminal_color_1  = colors.red
vim.g.terminal_color_2  = colors.green
vim.g.terminal_color_3  = colors.yellow
vim.g.terminal_color_4  = colors.blue
vim.g.terminal_color_5  = colors.purple   -- magenta
vim.g.terminal_color_6  = colors.cyan
vim.g.terminal_color_7  = colors.fg       -- white
vim.g.terminal_color_8  = colors.dark     -- bright black
vim.g.terminal_color_9  = colors.pink     -- bright red
vim.g.terminal_color_10 = colors.lime     -- bright green
vim.g.terminal_color_11 = colors.orange   -- bright yellow
vim.g.terminal_color_12 = colors.blue     -- bright blue
vim.g.terminal_color_13 = colors.purple   -- bright magenta
vim.g.terminal_color_14 = colors.emerald  -- bright cyan
vim.g.terminal_color_15 = colors.white    -- bright white

