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

local function time(fn)
  local start = vim.uv.hrtime()
  fn()
  return (vim.uv.hrtime() - start) / 1e6
end
local function heap()
  collectgarbage("collect")
  return collectgarbage("count") / 1024
end
local baseline = heap()
local dictionary
local result = { bytes = assert(vim.uv.fs_stat(path)).size }
result.open_ms = time(function()
  dictionary = reader.open(path)
end)
result.entries = dictionary.count
result.first_lookup_ms = time(function()
  dictionary.lookup("woudl")
end)
result.first_bucket_heap_mib = heap() - baseline

local cold = { result.first_lookup_ms }
local first_bucket = reader.bucket("woudl")
for bucket, query in ipairs(queries) do
  if bucket ~= first_bucket then
    cold[#cold + 1] = time(function()
      dictionary.lookup(query)
    end)
  end
end
result.all_buckets_heap_mib = heap() - baseline
table.sort(cold)
result.cold_bucket_median_ms = (cold[128] + cold[129]) / 2
result.cold_bucket_p95_ms = cold[math.ceil(#cold * 0.95)]
local lookup_count = 100000
result.cached_lookup_us = time(function()
  for index = 1, lookup_count do
    dictionary.lookup(queries[(index - 1) % 256 + 1])
  end
end) * 1000 / lookup_count
dictionary.close()
print(vim.json.encode(result))
