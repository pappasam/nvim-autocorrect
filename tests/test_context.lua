-- Exercise real input: context must be current before a separator expands it.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:remove(vim.fn.stdpath("data") .. "/site")
vim.o.showmode = false
local plugin = require("autocorrect")
plugin.setup({
  filetypes = { "markdown", "lua", "c", "text", "gitcommit", "unknown" },
})

local function check(ft, before, keys, expected, syntax)
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = ft
  vim.bo.autoindent = false
  vim.bo.smartindent = false
  vim.bo.indentexpr = ""
  vim.bo.formatoptions = ""
  vim.bo.syntax = ""
  if syntax then
    vim.cmd("runtime syntax/" .. ft .. ".vim")
    vim.cmd("syntax sync fromstart")
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, before)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(
    vim.deep_equal(actual, expected),
    vim.inspect({
      ft = ft,
      before = before,
      keys = keys,
      actual = actual,
      expected = expected,
    })
  )
  assert(#vim.api.nvim_buf_get_keymap(0, "ia") == 0, "Context mappings leaked")
end

local function markdown_cases(syntax, embedded_comments)
  local function md(before, keys, expected)
    check("markdown", before, keys, expected, syntax)
  end
  md(
    { "" },
    "idefinately `definately` definately <Esc>",
    { "definitely `definately` definitely " }
  )
  md({ "" }, "i`definately <Esc>", { "`definately " })
  md(
    { "" },
    "i``definately ` definately`` definately <Esc>",
    { "``definately ` definately`` definitely " }
  )
  md({ "" }, "i\\`definately <Esc>", { "\\`definitely " })
  md(
    { "" },
    "i```definately``` definately <Esc>",
    { "```definately``` definitely " }
  )
  md(
    { "> ```", "> code", "" },
    "GAdefinately <Esc>",
    { "> ```", "> code", "definitely " }
  )
  md({ "" }, "i```lua<CR>-- definately<CR>```<CR>definately <Esc>", {
    "```lua",
    embedded_comments and "-- definitely" or "-- definately",
    "```",
    "definitely ",
  })
  md(
    { "~~~~lua", "", "~~~~" },
    "jidefinately <Esc>",
    { "~~~~lua", "definately ", "~~~~" }
  )
  md(
    { "```", "```", "" },
    "Gidefinately <Esc>",
    { "```", "```", "definitely " }
  )
  md(
    { "> ```lua", "> ", "> ```" },
    "jAdefinately <Esc>",
    { "> ```lua", "> definately ", "> ```" }
  )
  md(
    { "- ```lua", "  ", "  ```" },
    "jAdefinately <Esc>",
    { "- ```lua", "  definately ", "  ```" }
  )
  md({ "", "    " }, "GAdefinately <Esc>", { "", "    definately " })
  md(
    { "`first", "" },
    "GAdefinately` definately <Esc>",
    { "`first", "definately` definitely " }
  )
  md(
    { "" },
    "i[definately](https://example.com/definately) definately <Esc>",
    { "[definitely](https://example.com/definately) definitely " }
  )
  md(
    { "" },
    "ihttps://example.com/definately www.definately.com definately@example.com <Esc>",
    {
      "https://example.com/definately www.definately.com definately@example.com ",
    }
  )
  md({ "" }, "i`definately<C-]><Esc>", { "`definately" })
  md({ "" }, "idefinately<C-V> <Esc>", { "definately " })
  md({ "" }, "idefinately <Esc>u<C-r>", { "definitely " })
  md(
    { "" },
    "qaidefinately `definately` <Esc>qo<Esc>@a",
    { "definitely `definately` ", "definitely `definately` " }
  )

  -- Editing a previously scanned fence must invalidate all later line states.
  md(
    { "```", "", "```" },
    "jidefinately <Esc>ggddGAdefinately <Esc>",
    { "definately ", "```definately " }
  )
  md(
    { "```", "", "```" },
    "jidefinately <Esc>ggccprose<Esc>jAdefinately <Esc>",
    { "prose", "definately definitely ", "```" }
  )
end

local function comment_cases(syntax)
  check(
    "lua",
    { "" },
    'ilocal value = "`" -- definately <Esc>',
    { 'local value = "`" -- definitely ' },
    syntax
  )
  check(
    "lua",
    { "" },
    'ilocal definately = "definately" -- definately <Esc>',
    { 'local definately = "definately" -- definitely ' },
    syntax
  )
  check(
    "lua",
    { "" },
    'ilocal value = "-- definately "<Esc>',
    { 'local value = "-- definately "' },
    syntax
  )
  check(
    "lua",
    { "" },
    "i-- definately `definately` definately <Esc>",
    { "-- definitely `definately` definitely " },
    syntax
  )
  check(
    "lua",
    { "-- ```lua", "-- ", "-- ```", "-- " },
    "jAdefinately <Esc>G Adefinately <Esc>",
    { "-- ```lua", "-- definately ", "-- ```", "-- definitely " },
    syntax
  )
  check(
    "c",
    { "/*", " * ```c", " * ", " * ```", " * ", " */" },
    "2jAdefinately <Esc>2jAdefinately <Esc>",
    { "/*", " * ```c", " * definately ", " * ```", " * definitely ", " */" },
    syntax
  )
  check(
    "lua",
    { "" },
    "i-- https://example.com/definately foo_definately definately <Esc>",
    { "-- https://example.com/definately foo_definately definitely " },
    syntax
  )
  check("lua", { "" }, "i-- definately<Esc>", { "-- definitely" }, syntax)
  check("lua", { "" }, "i-- definately<C-]><Esc>", { "-- definitely" }, syntax)
  check(
    "lua",
    { "" },
    "i-- definately<C-V> <Esc>",
    { "-- definately " },
    syntax
  )
  check(
    "lua",
    { "" },
    "i-- definately <Esc>odefinately <Esc>",
    { "-- definitely ", "definately " },
    syntax
  )
end

-- Bundled parsers, without enabling Tree-sitter highlighting.
assert(vim.treesitter.get_parser(0, "markdown"))
assert(vim.treesitter.get_parser(0, "lua"))
assert(vim.treesitter.get_parser(0, "c"))
markdown_cases(false, true)
comment_cases(false)
check(
  "markdown",
  { "[label](definately)" },
  "0f)i <Esc>",
  { "[label](definately )" }
)

-- No parser: legacy syntax identifies comments, including nested Todo groups.
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function()
  error("Parser unavailable")
end
markdown_cases(true)
comment_cases(true)
check(
  "lua",
  { "" },
  "i-- TODO definately <Esc>",
  { "-- TODO definitely " },
  true
)

-- No parser and no syntax: Markdown still has lexical protection; code is off.
markdown_cases(false)
check("lua", { "" }, "i-- definately <Esc>", { "-- definately " })
check("unknown", { "" }, "idefinately <Esc>", { "definately " })
check("text", { "" }, "idefinately <Esc>", { "definitely " })
check("gitcommit", { "" }, "idefinately <Esc>", { "definitely " })
vim.treesitter.get_parser = get_parser

-- Reconfiguration keeps context checks and capitalization independent.
plugin.setup({ filetypes = { "lua", "markdown" }, correct_capitalized = true })
check(
  "lua",
  { "" },
  "i-- Definately `Definately` <Esc>",
  { "-- Definitely `Definately` " }
)
check(
  "markdown",
  { "" },
  "iDefinately `Definately` <Esc>",
  { "Definitely `Definately` " }
)
print(
  "PASS: Markdown code, comments, live context changes, parser/syntax fallbacks"
)
vim.cmd("qa!")
