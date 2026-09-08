-- Run from the repository root:
-- nvim -u NONE --headless -i NONE -l tests/test_autocorrect.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.o.showmode = false

local plugin = require("autocorrect")
local bytes_read = 0
local read = vim.uv.fs_read
vim.uv.fs_read = function(fd, size, offset, ...)
  bytes_read = bytes_read + size
  return read(fd, size, offset, ...)
end
plugin.setup()
vim.bo.filetype = "markdown"
vim.uv.fs_read = read
assert(bytes_read < 16384, "Startup read more than dictionary metadata")
vim.api.nvim_clear_autocmds({ group = "NvimAutocorrect" })

local reference = {
  woudl = "would",
  definately = "definitely",
  seperately = "separately",
  eachother = "each other",
  fromthe = "from the",
}
local cases = {
  { "iwoudl <Esc>" },
  { "iwoudl<CR>woudl<Esc>" },
  { "iwoudl<C-]>!<Esc>" },
  { "iwoudl<C-V> <Esc>" },
  { "iwoudl<C-c>" },
  { "iwoudl definately <Esc>u" },
  { "iwoudl definately <Esc>u<C-r>" },
  { "iwoudl <Esc>0." },
  { "qaiwoudl <Esc>qo<Esc>@a" },
  { "Awoudl<Left><Right> <Esc>", "prefix" },
  { "iwoudl definately Woudl WOUDL wOuDl seperately.<Esc>" },
  { "ifoo_woudl foo-woudl éwoudl woudlé <Esc>" },
  { "iwoudl<Tab>woudl!woudl,woudl?woudl;woudl:woudl)<Esc>" },
  { "iwoudl<BS>l <Esc>" },
  { "iwoudl<C-w>woudl <Esc>" },
  { "Rwoudl <Esc>", "xxxxx" },
  { "gRwoudl <Esc>", "xxxxx" },
  { "iwoudl<C-o>0<End> <Esc>" },
  { "ifoo-woudl woudl <Esc>", "", 0, "@,48-57,_,-" },
  { "ieachother fromthe.<Esc>" },
  { "ieachother<CR>fromthe<C-]>!<Esc>" },
  { "ieachother<C-V> <Esc>" },
  { "ieachother fromthe <Esc>u<C-r>" },
  { "ieachother <Esc>0." },
  { "qbieachother <Esc>qo<Esc>@b" },
  { "ieachother<Tab>fromthe,eachother!<Esc>" },
}

local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end

local function run(case, native)
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = "markdown"
  vim.bo.iskeyword = case[4] or "@,48-57,_,192-255"
  if case[2] then
    vim.api.nvim_set_current_line(case[2])
    vim.api.nvim_win_set_cursor(0, { 1, case[3] or 0 })
  end
  if native then
    for lhs, rhs in pairs(reference) do
      vim.keymap.set("ia", lhs, rhs, { buffer = 0 })
    end
  end
  feed(case[1])
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local expected = {}
for i, case in ipairs(cases) do
  expected[i] = run(case, true)
end
plugin.setup()
for i, case in ipairs(cases) do
  local actual = run(case, false)
  assert(
    vim.deep_equal(expected[i], actual),
    vim.inspect({
      keys = case[1],
      expected = expected[i],
      actual = actual,
    })
  )
  assert(#vim.api.nvim_buf_get_keymap(0, "ia") == 0, "Mappings leaked")
end

local dictionary = require("autocorrect.dictionary").open(
  require("autocorrect.cache").path(vim.fn.getcwd())
)
for typo, correction in pairs({
  seperately = "separately",
  sepparately = "separately",
  cconfiguration = "configuration",
  accommmodation = "accommodation",
  looknig = "looking",
  meeitng = "meeting",
  upadted = "updated",
  payemnts = "payments",
  pracitcal = "practical",
  partenrship = "partnership",
  requirse = "requires",
  accounst = "accounts",
  achievde = "achieved",
  mgiht = "might",
  mihgt = "might",
  rgiht = "right",
  wolrd = "world",
  abotu = "about",
  hte = "the",
  seperate = "separate",
  wiht = "with",
  wtih = "with",
  taht = "that",
  thsi = "this",
  yuo = "you",
  tthe = "the",
  knwo = "know",
  hwere = "where",
  wehther = "whether",
  aviod = "avoid",
  birng = "bring",
  whch = "which",
  whih = "which",
  wgich = "which",
  probebly = "probably",
  rimember = "remember",
  thousend = "thousand",
  peolpe = "people",
  pepole = "people",
  eachother = "each other",
  fromthe = "from the",
  wantto = "want to",
}) do
  assert(dictionary.lookup(typo) == correction, typo)
end
assert(dictionary.lookup("wOuDl") == nil)
assert(dictionary.lookup("correct") == nil)
assert(
  run(
    { "iwehther weather whether Wehther WEHTHER foo_wehther wehtherx.<Esc>" },
    false
  )[1]
    == "whether weather whether Wehther WEHTHER foo_wehther wehtherx."
)
assert(
  run({ "iwhch wgich probebly rimember thousend peolpe pepole.<Esc>" }, false)[1]
    == "which which probably remember thousand people people."
)
assert(
  run({ "iWhch WGICH foo_peolpe peopelx dont alot.<Esc>" }, false)[1]
    == "Whch WGICH foo_peolpe peopelx dont alot."
)
assert(
  run(
    { "iEachother EACHOTHER foo_eachother eachotherx xeachother.<Esc>" },
    false
  )[1] == "Eachother EACHOTHER foo_eachother eachotherx xeachother."
)
assert(
  run(
    { "idont didnt isnt its were well alot aswell infact overthere.<Esc>" },
    false
  )[1] == "dont didnt isnt its were well alot aswell infact overthere."
)

-- Preserve all letters when a unique adjacent swap competes only with deletions.
assert(
  run({ "irequirse accounst achievde.<Esc>" }, false)[1]
    == "requires accounts achieved."
)

-- Five-letter swaps pass the length gate while retaining normal word boundaries.
assert(
  run({ "imgiht mihgt rgiht wolrd.<Esc>" }, false)[1]
    == "might might right world."
)

-- Precision takes precedence over guessing names, abbreviations, or valid words.
assert(
  run({ "ihte abotu seperate abilith abilityy <Esc>" }, false)[1]
    == "the about separate ability ability "
)
local protected = "algin adust belive grammer siad teh thier form from staring "
  .. "starting publically supercede NASA NATO SaaS OpenAI Teh Thier Seperate SEPERATE"
  .. " Definately DEFINATELY looking meeting updated payments practical partnership"
  .. " severate sperate superate"
  .. " require requires trails trials united untied Requirse REQUIRSE foo_requirse"
  .. " might right world trial trail quiet quite Mgiht MGIHT foo_mgiht fomr mighx"
  .. " buidl Buidl BUIDL build"
  .. " Hte HTE Abotu ABOTU foo_hte foo_abotu"
  .. " buidling Buidling BUIDLING"
  .. " wth mayu th fo ot Wiht WIHT foo_wiht whit with form from"
  .. " where here were twere Hwere HWERE foo_hwere"
assert(run({ "i" .. protected .. " <Esc>" }, false)[1] == protected .. " ")
assert(
  run({ "iwiht wtih taht thsi yuo tthe knwo.<Esc>" }, false)[1]
    == "with with that this you the know."
)
assert(run({ "iwiht<C-V> <Esc>" }, false)[1] == "wiht ")
assert(
  run({ "ihwere aviod birng wehat.<Esc>" }, false)[1]
    == "where avoid bring what."
)
assert(run({ "ihwere<C-V> <Esc>" }, false)[1] == "hwere ")
assert(run({ "Adefinately <Esc>", "prefix" }, false)[1] == "prefixdefinately ")
assert(run({ "Adefinately <Esc>", "Name" }, false)[1] == "Namedefinately ")
assert(run({ "Adefinately <Esc>", "foo_" }, false)[1] == "foo_definately ")
assert(run({ "iwoudl<Esc>", "suffix" }, false)[1] == "woudlsuffix")
assert(run({ "iwoudl<C-]><Esc>", "suffix" }, false)[1] == "woudlsuffix")
assert(run({ "iwoudl <Esc>", "suffix" }, false)[1] == "would suffix")
local long_prefix = ("x"):rep(100000)
assert(
  run({ "Adefinately <Esc>", long_prefix }, false)[1]
    == long_prefix .. "definately "
)

-- Explicit user abbreviations take precedence and survive teardown.
vim.cmd.enew({ bang = true })
vim.bo.filetype = "gitcommit"
vim.keymap.set("ia", "woudl", "custom", { buffer = 0 })
feed("iwoudl definately <Esc>")
assert(vim.api.nvim_get_current_line() == "custom definitely ")
assert(vim.fn.maparg("woudl", "i", true) == "custom")
assert(#vim.api.nvim_buf_get_keymap(0, "ia") == 1)
vim.bo.filetype = "lua"
feed("odefinately <Esc>")
assert(vim.api.nvim_get_current_line() == "definately ")

-- Many buffers should neither duplicate the dictionary nor install mappings.
local loaded = package.loaded["autocorrect.dictionary"]
for _ = 1, 30 do
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = "markdown"
  assert(#vim.api.nvim_buf_get_keymap(0, "ia") == 0)
  assert(package.loaded["autocorrect.dictionary"] == loaded)
end

-- Exercise a long line and inspect the bounded native set during insertion.
local count
vim.keymap.set("i", "<F12>", function()
  count = #vim.api.nvim_buf_get_keymap(0, "ia")
end)
vim.api.nvim_set_current_line(("x"):rep(100000))
feed("A woudl <F12><Esc>")
assert(vim.api.nvim_get_current_line():sub(-7) == " would ")
assert(count and count <= 2)
plugin.setup()
plugin.setup()
feed("owoudl <Esc>")
assert(vim.api.nvim_get_current_line() == "would ")

-- Every source mapping must round-trip; capitalized/all-caps inputs are protected.
local count_mappings = 0
for typo, correction in
  pairs(require("autocorrect.source").load("data/corrections.json"))
do
  assert(dictionary.lookup(typo) == correction, typo)
  assert(dictionary.lookup(typo:upper()) == nil, typo)
  local title = typo:sub(1, 1):upper() .. typo:sub(2)
  assert(dictionary.lookup(title) == nil, title)
  count_mappings = count_mappings + 1
end
assert(dictionary.count == count_mappings)
dictionary.close()
print(
  ("PASS: %d lowercase mappings plus capitalization guards"):format(
    count_mappings
  )
)

print(
  ("PASS: %d native behavior comparisons and lifecycle checks"):format(#cases)
)
vim.cmd("qa!")
