-- nvim -u NONE --headless -i NONE -l tests/benchmark_dictionary.lua [dictionary.mpack]
-- Run each sample in a fresh process. OS file caches may already be warm.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local reader = require("autocorrect.dictionary")
local path = arg[1] or require("autocorrect.cache").path(vim.fn.getcwd())
local queries, remaining, number = {}, 256, 0
while remaining > 0 do
  number = number + 1
  local suffix, value = "", number
  repeat
    suffix = string.char(97 + value % 26) .. suffix
    value = math.floor(value / 26)
  until value == 0
  local query = "benchmark" .. suffix
  local bucket = reader.bucket(query)
  if not queries[bucket] then
    queries[bucket] = query
    remaining = remaining - 1
  end
end

-- Select real entries before timing: a filtered miss no longer loads a bucket.
local hits = {}
local fd = assert(vim.uv.fs_open(path, "r", 438))
local header_size = tonumber(assert(vim.uv.fs_read(fd, 8, 0)), 16)
local header = vim.mpack.decode(assert(vim.uv.fs_read(fd, header_size, 8)))
assert(header[1] == 5, "Rebuild the dictionary before benchmarking")
for bucket, location in ipairs(header[4]) do
  local partition = vim.mpack.decode(
    assert(
      vim.uv.fs_read(
        fd,
        location[2] - location[3],
        8 + header_size + location[1] + location[3]
      )
    )
  )
  hits[bucket] = partition[1][1]
end
assert(vim.uv.fs_close(fd))
local prose, seen = {}, {}
for _, line in ipairs(vim.fn.readfile("README.md")) do
  for word in line:gmatch("[a-z]+") do
    if not seen[word] then
      seen[word] = true
      prose[#prose + 1] = word
    end
  end
end
seen, header = nil, nil

local function time(fn)
  local start = vim.uv.hrtime()
  fn()
  return (vim.uv.hrtime() - start) / 1e6
end
local function heap()
  collectgarbage("collect")
  return collectgarbage("count") / 1024
end
local function workload(words)
  local baseline = heap()
  local dictionary = reader.open(path)
  local decode, partitions = vim.mpack.decode, 0
  vim.mpack.decode = function(...)
    partitions = partitions + 1
    return decode(...)
  end
  local elapsed = time(function()
    for _, word in ipairs(words) do
      dictionary.lookup(word)
    end
  end)
  vim.mpack.decode = decode
  local result = {
    words = #words,
    lookup_ms = elapsed,
    heap_mib = heap() - baseline,
    partitions = partitions,
  }
  dictionary.close()
  return result
end

local result = {
  bytes = assert(vim.uv.fs_stat(path)).size,
  negative_queries = workload(queries),
  readme_queries = workload(prose),
}
local baseline = heap()
local dictionary
result.open_ms = time(function()
  dictionary = reader.open(path)
end)
result.entries = dictionary.count
local first_bucket = reader.bucket("woudl")
if not hits[first_bucket] then
  first_bucket = next(hits)
end
assert(first_bucket, "Benchmark requires a nonempty dictionary")
result.first_lookup_ms = time(function()
  dictionary.lookup(hits[first_bucket])
end)
result.first_bucket_heap_mib = heap() - baseline

local cold = { result.first_lookup_ms }
for bucket, query in pairs(hits) do
  if bucket ~= first_bucket then
    cold[#cold + 1] = time(function()
      dictionary.lookup(query)
    end)
  end
end
result.all_buckets_heap_mib = heap() - baseline
table.sort(cold)
result.cold_bucket_median_ms = (
  cold[math.ceil(#cold / 2)] + cold[math.floor(#cold / 2) + 1]
) / 2
result.cold_bucket_p95_ms = cold[math.ceil(#cold * 0.95)]
local lookup_count = 100000
result.cached_lookup_us = time(function()
  for index = 1, lookup_count do
    dictionary.lookup(queries[(index - 1) % 256 + 1])
  end
end) * 1000 / lookup_count
dictionary.close()
print(vim.json.encode(result))
