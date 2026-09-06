vim.opt.runtimepath:prepend(vim.fn.getcwd())
local source = require("autocorrect.source")
local path = vim.fn.tempname()
local cases = vim.json.decode(
  table.concat(vim.fn.readfile("tests/source_cases.json"), "\n")
)
for _, case in ipairs(cases) do
  vim.fn.writefile({ case.source }, path)
  local ok, entries = pcall(source.load, path)
  if case.expected then
    assert(ok, entries)
    assert(vim.deep_equal(entries, case.expected), case.name)
  else
    assert(not ok, "Accepted invalid source: " .. case.name)
  end
end
vim.fn.delete(path)
print(("PASS: %d JSON source validation cases"):format(#cases))
