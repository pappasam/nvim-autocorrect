-- nvim -u NONE --headless -i NONE -l <this file> [--check]
local config = vim.fs.dirname(
  vim.fs.dirname(
    assert(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
  )
)
local dictionary = dofile(config .. "/lua/autocorrect/dictionary.lua")
local source = dofile(config .. "/lua/autocorrect/source.lua")
local cache = dofile(config .. "/lua/autocorrect/cache.lua")
local fingerprint = cache.fingerprint(config)
local corrections = source.load(config .. "/data/corrections.json")
local buckets = {}
for index = 1, 256 do
  buckets[index] = {}
end
local max_length, count = 0, 0
for typo in pairs(corrections) do
  count = count + 1
  max_length = math.max(max_length, #typo)
  table.insert(buckets[dictionary.bucket(typo)], typo)
end

local locations, chunks = {}, {}
local offset = 0
for index, typos in ipairs(buckets) do
  table.sort(typos)
  local entries = {}
  for _, typo in ipairs(typos) do
    table.insert(entries, typo)
    table.insert(entries, corrections[typo])
  end
  local chunk = vim.mpack.encode(entries)
  locations[index] = { offset, #chunk }
  chunks[index] = chunk
  offset = offset + #chunk
end
-- Arrays keep the output deterministic across Lua hash iteration orders.
local header =
  vim.mpack.encode({ 3, count, max_length, locations, fingerprint })
local bytes = ("%08x"):format(#header) .. header .. table.concat(chunks)
local output = cache.path(config)
output = vim.uv.fs_realpath(output) or output
local function read_existing()
  local fd = vim.uv.fs_open(output, "r", 438)
  if not fd then
    return nil
  end
  local existing = vim.uv.fs_read(fd, assert(vim.uv.fs_fstat(fd)).size, 0)
  vim.uv.fs_close(fd)
  return existing
end
local current = read_existing() == bytes
assert(
  cache.fingerprint(config) == fingerprint,
  "Dictionary inputs changed during the build; retry :AutocorrectBuild"
)
if arg[1] == "--check" then
  assert(current, "Generated dictionary is stale; run make build")
elseif not current then
  vim.fn.mkdir(vim.fs.dirname(output), "p")
  local temporary = output .. "." .. vim.fn.getpid() .. ".tmp"
  local fd = assert(vim.uv.fs_open(temporary, "w", 420))
  assert(vim.uv.fs_write(fd, bytes, 0) == #bytes)
  assert(vim.uv.fs_close(fd))
  -- Existing readers retain a consistent snapshot through their open fd.
  assert(vim.uv.fs_rename(temporary, output))
end
print(output)
