-- nvim -u NONE --headless -i NONE -l tests/benchmark.lua [count|source.json]
-- Builds the fixture before timing. Use a fresh process for each sample.
vim.o.showmode = false
vim.o.undolevels = -1
local original = vim.fn.getcwd()
local config = dofile("tests/helpers.lua").fixture()
local count = tonumber(arg[1])
if count then
  local entries = { would = { "woudl" } }
  for index = 1, count do
    local suffix, number = "", index
    repeat
      suffix = string.char(97 + number % 26) .. suffix
      number = math.floor(number / 26)
    until number == 0
    entries["correction" .. suffix] = { "typo" .. suffix }
  end
  vim.fn.writefile(
    { vim.json.encode(entries) },
    config .. "/data/corrections.json"
  )
else
  assert(
    vim.uv.fs_copyfile(
      arg[1] or original .. "/data/corrections.json",
      config .. "/data/corrections.json"
    )
  )
end
local result = vim
  .system({
    vim.v.progpath,
    "-u",
    "NONE",
    "--headless",
    "-i",
    "NONE",
    "-l",
    config .. "/scripts/build-dictionary.lua",
  }, { text = true })
  :wait()
assert(result.code == 0, result.stderr)
collectgarbage("collect")
vim.opt.runtimepath:prepend(config)

local function time(fn)
  local start = vim.uv.hrtime()
  fn()
  return (vim.uv.hrtime() - start) / 1e6
end
local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end
local timings = {}
timings.setup_ms = time(function()
  require("autocorrect").setup()
end)
timings.filetype_ms = time(function()
  vim.bo.filetype = "markdown"
end)
timings.first_insert_ms = time(function()
  feed("iwoudl <Esc>")
end)
timings.six_thousand_words_ms = time(function()
  feed("o" .. ("ordinary missing woudl<CR>"):rep(2000) .. "<Esc>")
end)
timings.next_buffer_ms = time(function()
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = "markdown"
end)
print(vim.json.encode(timings))
dofile(original .. "/tests/helpers.lua").cleanup(config)
vim.cmd("qa!")
