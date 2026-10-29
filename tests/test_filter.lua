vim.opt.runtimepath:prepend(vim.fn.getcwd())
local filter = require("autocorrect.filter")
local reader = require("autocorrect.dictionary")
local path = require("autocorrect.cache").path(vim.fn.getcwd())
local fd = assert(vim.uv.fs_open(path, "r", 438))
local size = tonumber(assert(vim.uv.fs_read(fd, 8, 0)), 16)
local header = vim.mpack.decode(assert(vim.uv.fs_read(fd, size, 8)))
local filters = {}
for index, location in ipairs(header[4]) do
  filters[index] =
    assert(vim.uv.fs_read(fd, location[3], 8 + size + location[1]))
end
assert(vim.uv.fs_close(fd))

-- Test every shipped spelling against its on-disk filter, including entries
-- whose exact bucket would already have been cached in the round-trip test.
local entries = require("autocorrect.source").load("data/corrections.json")
for word in pairs(entries) do
  assert(filter.contains(filters[reader.bucket(word)], word), word)
end
assert(not filter.contains(filter.build({}), "anything"))
assert(filter.build({ "one", "two" }) == filter.build({ "two", "one" }))

local dictionary = reader.open(path)
local decode, read = vim.mpack.decode, vim.uv.fs_read
local partitions, bytes = 0, 0
vim.mpack.decode = function(...)
  partitions = partitions + 1
  return decode(...)
end
vim.uv.fs_read = function(file, length, offset)
  bytes = bytes + length
  return read(file, length, offset)
end
for number = 1, 4096 do
  local word, value = "absent", number
  repeat
    word = word .. string.char(97 + value % 26)
    value = math.floor(value / 26)
  until value == 0
  assert(entries[word] == nil)
  assert(dictionary.lookup(word) == nil)
  local previous = bytes
  assert(dictionary.lookup(word) == nil)
  assert(bytes == previous, "Repeated miss reread its filter")
end
vim.mpack.decode, vim.uv.fs_read = decode, read
assert(partitions < 80, "Too many negative lookups decoded full partitions")
assert(
  bytes < vim.uv.fs_stat(path).size / 4,
  "Misses read too much dictionary data"
)
dictionary.close()

-- Exercise damaged filters and deliberate false positives through the real
-- reader. Neither may change exact corrections or capitalization eligibility.
local helpers = dofile("tests/helpers.lua")
local root = helpers.fixture()
vim.fn.writefile(
  { '{"probably":["probebly"]}' },
  root .. "/data/corrections.json"
)
vim.fn.writefile(
  { '{"probably":["probebly"]}' },
  root .. "/data/capitalized-corrections.json"
)
local result = vim
  .system({
    vim.v.progpath,
    "-u",
    "NONE",
    "--headless",
    "-i",
    "NONE",
    "-l",
    root .. "/scripts/build-dictionary.lua",
  }, { text = true })
  :wait()
assert(result.code == 0, result.stderr)
path = helpers.output(root)
fd = assert(vim.uv.fs_open(path, "r", 438))
local original =
  assert(vim.uv.fs_read(fd, assert(vim.uv.fs_fstat(fd)).size, 0))
assert(vim.uv.fs_close(fd))
size = tonumber(original:sub(1, 8), 16)
for _, damaged in ipairs({ true, false }) do
  header = decode(original:sub(9, 8 + size))
  local chunks = {}
  for _, location in ipairs(header[4]) do
    local membership = (damaged and "\0" or "\255"):rep(location[3])
    if not damaged then
      location[4] = vim.fn.sha256(membership):sub(1, 16)
    end
    chunks[#chunks + 1] = membership
      .. original:sub(
        9 + size + location[1] + location[3],
        8 + size + location[1] + location[2]
      )
  end
  local updated = vim.mpack.encode(header)
  local bytes = ("%08x"):format(#updated) .. updated .. table.concat(chunks)
  fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, bytes, 0) == #bytes)
  assert(vim.uv.fs_close(fd))
  dictionary = reader.open(path)
  assert(dictionary.lookup("probebly") == "probably")
  assert(dictionary.lookup("Probebly", true) == "Probably")
  assert(dictionary.lookup("Probebly") == nil)
  assert(dictionary.lookup("unknown") == nil)
  dictionary.close()
end
helpers.cleanup(root)
print(
  ("PASS: all on-disk filters, cached misses (%d partitions), corruption and false positives"):format(
    partitions
  )
)
