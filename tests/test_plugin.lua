-- Run from the plugin repository root with nvim -u NONE --headless -i NONE -l.
vim.o.showmode = false
local root = vim.fn.getcwd()
local site = vim.fn.tempname()
vim.fn.mkdir(site .. "/pack/core/opt", "p")
assert(vim.uv.fs_symlink(root, site .. "/pack/core/opt/nvim-autocorrect"))
vim.opt.packpath:prepend(site)
vim.g.nvim_autocorrect = { filetypes = { "text" }, correct_capitalized = true }
vim.cmd.packadd("nvim-autocorrect")
assert(vim.g.loaded_nvim_autocorrect)
assert(vim.fn.exists(":AutocorrectBuild") == 2)

local function check(filetype, expected, word)
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = filetype
  vim.api.nvim_feedkeys(
    vim.keycode("i" .. (word or "definately") .. " <Esc>"),
    "xt",
    false
  )
  assert(vim.api.nvim_get_current_line() == expected, filetype)
  assert(#vim.api.nvim_buf_get_keymap(0, "ia") == 0)
end

check("text", "definitely ")
check("text", "Definitely ", "Definately")
check("markdown", "Definately ", "Definately")
check("markdown", "definately ")
local plugin = require("autocorrect")
plugin.setup({ filetypes = {} })
check("text", "definately ")
plugin.setup({ filetypes = { "lua" } })
-- Loading the entrypoint again must preserve explicit Lua configuration.
vim.cmd.runtime("plugin/autocorrect.lua")
check("lua", "definately ")
check("lua", "-- definitely ", "-- definately")
check("text", "definately ")
plugin.setup()
check("markdown", "definitely ")
check("markdown", "Definately ", "Definately")
check("gitcommit", "definitely ")
check("lua", "definately ")
local hooks = #vim.api.nvim_get_autocmds({ group = "NvimAutocorrect" })
vim.cmd.packadd("nvim-autocorrect")
assert(#vim.api.nvim_get_autocmds({ group = "NvimAutocorrect" }) == hooks)
vim.fn.delete(site, "rf")
print(
  "PASS: optional package loading, configuration, defaults, repeated loading"
)
vim.cmd("qa!")
