-- Set the name of the theme
vim.g.colors_name = "kinder_theme"
vim.o.background = 'dark'

-- Clear existing highlights
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end

-- Define colors
local colors = {
	bg      = "#262626",
	fg      = "#DCDCDC",
	red     = "#FC6161",
	green   = "#7BD88F",
	yellow  = "#FCE566",
	orange  = "#FFA348",
	blue    = "#61AFEF",
	purple  = "#948AE3",
	cyan    = "#5AD4E6",
	pink    = "#FC618D",
	emerald = "#00DCC3",
	white   = "#F7F1FF",
	gray    = "#ABB2BF",
	dark    = "#5A5A5A",
	brown   = "#71504D"
}

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

-- Different background color if using Neovide
if vim.g.neovide then
	vim.api.nvim_set_hl(0, "Normal", { bg = colors.bg })
	vim.api.nvim_set_hl(0, "NormalFloat", { bg = colors.bg })
end

-- Default highlights. Use ":Inspect" command to find correct type.
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
vim.api.nvim_set_hl(0, "Comment", { fg = colors.dark })
vim.api.nvim_set_hl(0, "WinSeparator", { fg = colors.dark })

-- CPP highlights
vim.api.nvim_set_hl(0, "@variable.cpp", { fg = colors.gray })
vim.api.nvim_set_hl(0, "@label.cpp", { fg = colors.red })
vim.api.nvim_set_hl(0, "@constructor.cpp", { fg = colors.green })
vim.api.nvim_set_hl(0, "@variable.parameter.cpp", { fg = colors.orange })
vim.api.nvim_set_hl(1, "@modele.cpp", { fg = colors.blue })
vim.api.nvim_set_hl(0, "@type.cpp", { fg = colors.blue })

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

-- Rust highlights for Treesitter
local rust_highlights = {
	["rustAttribute"] = { fg = colors.dark },
	["rustDerive"] = { fg = colors.dark },
	["rustFoldBraces"] = { fg = colors.gray },
	["rustSigil"] = { fg = colors.red },
	--
	["@keyword.rust"] = { fg = colors.red },                -- Keywords (fn, let, etc.)
	["@keyword.storate.rust"] = { fg = colors.red },        -- Keywords (mut, &, etc.)
	["@function.rust"] = { fg = colors.green },             -- Function names
	["@function.call.rust"] = { fg = colors.green },        -- Function calls
	["@macro.rust"] = { fg = colors.brown },                -- Macros (derive!, etc.)
	["@type.rust"] = { fg = colors.blue },                  -- Types (i32, String, your enums)
	["@type.builtin.rust"] = { fg = colors.cyan },          -- Built-in types
	["@field.rust"] = { fg = colors.gray },                 -- Struct/enum fields
	["@variable.rust"] = { fg = colors.white },             -- Variables
	["@variable.parameter.rust"] = { fg = colors.orange },  -- Function parameters
	["@comment.rust"] = { fg = colors.dark },               -- Comments
	["@string.rust"] = { fg = colors.yellow },              -- Strings
	["@number.rust"] = { fg = colors.purple },              -- Numbers
	["@operator.rust"] = { fg = colors.red },               -- Operators (+, -, *, etc.)
	["@punctuation.bracket.rust"] = { fg = colors.gray },   -- Brackets ([, ], {, })
	["@punctuation.delimiter.rust"] = { fg = colors.gray }, -- Delimiters (,, ;, .)
	["@attribute.rust"] = { fg = colors.cyan },             -- Attributes (#derive, etc.)
	["@namespace.rust"] = { fg = colors.blue },             -- Namespaces/modules
	["@constructor.rust"] = { fg = colors.green },          -- Constructors (e.g., `MyStruct {}`)
	-- LSP Semantic highlight
	["@lsp.type.enum.rust"] = { fg = colors.cyan },
	["@lsp.type.enumMember.rust"] = { fg = colors.pink },
	["@lsp.type.decorator.rust"] = { fg = colors.dark },
	["@lsp.type.attributeBracket.rust"] = { fg = colors.dark },
	["@lsp.type.derive.rust"] = { fg = colors.cyan },
	["@lsp.type.builtinType.rust"] = { fg = colors.red },
	["@lsp.type.struct.rust"] = { fg = colors.blue },
	["@lsp.type.parameter.rust"] = { fg = colors.orange },
	["@lsp.type.builtinAttribute.rust"] = { fg = colors.dark },
	["@lsp.type.deriveHelper.rust"] = { fg = colors.dark },
	["@lsp.mode.attribute.rust"] = { fg = colors.dark },
	["@lsp.type.namespace.rust"] = { fg = colors.dark },
	["@lsp.type.macro.rust"] = { fg = colors.brown, bold = true },
	["@lsp.type.interface.rust"] = { fg = colors.cyan },
}
for group, color in pairs(rust_highlights) do
	vim.api.nvim_set_hl(0, group, color)
end

