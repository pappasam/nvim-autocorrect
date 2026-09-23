-- Real parsers, real input, and no highlighter required.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.showmode = false
require("autocorrect").setup({
  filetypes = { "markdown" },
  correct_capitalized = true,
})

local function check(before, keys, expected)
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = "markdown"
  vim.bo.autoindent = false
  vim.bo.smartindent = false
  vim.bo.indentexpr = ""
  vim.bo.formatoptions = ""
  vim.api.nvim_buf_set_lines(0, 0, -1, false, before)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(
    vim.deep_equal(actual, expected),
    vim.inspect({
      before = before,
      keys = keys,
      actual = actual,
      expected = expected,
    })
  )
  assert(
    #vim.api.nvim_buf_get_keymap(0, "ia") == 0,
    "Injected comment mappings leaked"
  )
end

local function fence(lang, prefix, keys, expected)
  check(
    { "```" .. lang, prefix, "```" },
    "jA" .. keys .. "<Esc>",
    { "```" .. lang, prefix .. expected, "```" }
  )
end

assert(vim.treesitter.language.add("markdown"))
for lang, leader in pairs({
  lua = "-- ",
  c = "// ",
  python = "# ",
  bash = "# ",
}) do
  local ok, available = pcall(vim.treesitter.language.add, lang)
  if lang == "lua" or lang == "c" then
    assert(ok and available, "Missing bundled parser: " .. lang)
  end
  if ok and available then
    fence(lang, leader, "Definately definately ", "Definitely definitely ")
    fence(lang, "", "definately ", "definately ")
    fence(lang, '"', leader .. 'definately" ', leader .. 'definately" ')
    fence(lang, "value = 1; " .. leader, "definately ", "definitely ")
    fence(lang, leader, "`definately` definately ", "`definately` definitely ")
    fence(
      lang,
      leader,
      "https://example.com/definately foo_definately ",
      "https://example.com/definately foo_definately "
    )
    fence(lang, leader, "definately", "definitely")
    fence(lang, leader, "definately<C-]>!", "definitely!")
    fence(lang, leader, "definately<C-V> ", "definately ")
    check(
      { "```" .. lang, leader },
      "jAdefinately <Esc>",
      { "```" .. lang, leader .. "definitely " }
    )
    check(
      { "~~~" .. lang, leader, "~~~" },
      "jAdefinately <Esc>",
      { "~~~" .. lang, leader .. "definitely ", "~~~" }
    )
    if lang == "python" then
      check(
        { "```python", '"""', "# ", '"""', "```" },
        "2jAdefinately <Esc>",
        { "```python", '"""', "# definately ", '"""', "```" }
      )
      check(
        { "```python", '"""', "# " },
        "2jAdefinately <Esc>",
        { "```python", '"""', "# definately " }
      )
    end
    print(
      "PASS: embedded "
        .. lang
        .. " comments, code/string guards, native controls"
    )
  else
    print("SKIP: optional " .. lang .. " parser not installed")
  end
end

-- Nested Markdown containers and block comments use buffer coordinates.
check(
  { "> ```lua", "> -- ", "> ```" },
  "jAdefinately <Esc>",
  { "> ```lua", "> -- definitely ", "> ```" }
)
check(
  { "- ```lua", "  -- ", "  ```" },
  "jAdefinately <Esc>",
  { "- ```lua", "  -- definitely ", "  ```" }
)
check(
  { "```c", "/*", " * ", " */", "```" },
  "2jAdefinately <Esc>",
  { "```c", "/*", " * definitely ", " */", "```" }
)
check(
  { "````lua", "-- ```", "-- ", "-- ```", "-- ", "````" },
  "2jAdefinately <Esc>2jAdefinately <Esc>",
  { "````lua", "-- ```", "-- definately ", "-- ```", "-- definitely ", "````" }
)

-- Inline code and fence delimiters never become eligible comments.
check(
  { "> ````lua", "> -- ~~~", "> -- ", "> -- ~~~", "> -- ", "> ````" },
  "2jAdefinately <Esc>2jAdefinately <Esc>",
  {
    "> ````lua",
    "> -- ~~~",
    "> -- definately ",
    "> -- ~~~",
    "> -- definitely ",
    "> ````",
  }
)
check({ "" }, "i`-- definately` <Esc>", { "`-- definately` " })
check({ "" }, "i```lua -- definately <Esc>", { "```lua -- definately " })
fence("", "-- ", "definately ", "definately ")
fence("autocorrect_missing_parser", "# ", "definately ", "definately ")

-- Editing the language or the comment marker must refresh injected trees.
check(
  { "```lua", "-- ", "```" },
  "jAdefinately <Esc>ggcc```autocorrect_missing_parser<Esc>jAdefinately <Esc>",
  { "```autocorrect_missing_parser", "-- definitely definately ", "```" }
)
check(
  { "```lua", "-- ", "```" },
  "jAdefinately <Esc>0ccvalue = '<Esc>Adefinately <Esc>",
  { "```lua", "value = 'definately ", "```" }
)
check(
  { "```lua", "-- `", "```", "```lua", "-- ", "```" },
  "4jAdefinately <Esc>",
  { "```lua", "-- `", "```", "```lua", "-- definitely ", "```" }
)

-- A parser failure must not fall back to broad Markdown syntax highlighting.
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function()
  error("No Markdown parser")
end
fence("lua", "-- ", "definately ", "definately ")
vim.treesitter.get_parser = get_parser

-- No injection query (or missing language parser): the Markdown root alone
-- cannot authorize a comment. Each check uses a fresh buffer/parser.
vim.treesitter.query.set("markdown", "injections", "")
fence("lua", "-- ", "definately ", "definately ")
vim.treesitter.query.set("markdown", "injections", nil)
fence("lua", "-- ", "definately ", "definitely ")

print(
  "PASS: fence boundaries, live edits, isolated blocks, and missing injection fallbacks"
)
vim.cmd("qa!")
