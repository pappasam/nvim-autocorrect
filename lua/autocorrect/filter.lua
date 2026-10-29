local M = {}
local bit = require("bit")

-- Mix both hashes after accumulating bytes: the dictionary's bucket hash
-- already fixes the low eight bits of a spelling-prefix hash.
local function mix(hash)
  hash = bit.tobit(hash + bit.lshift(hash, 3))
  hash = bit.bxor(hash, bit.rshift(hash, 11))
  return bit.tobit(hash + bit.lshift(hash, 15))
end

local function hashes(word, bits)
  local first, second = 5381, 0
  for index = 1, #word do
    local byte = word:byte(index)
    first = bit.tobit(first * 33 + byte)
    second = bit.tobit(second * 65599 + byte)
  end
  return mix(first) % bits, mix(second) % bits
end

-- Twelve bits per entry and eight probes keep filters small while rejecting
-- most misses. Positives must always be checked against the exact dictionary.
function M.build(words)
  local size = math.max(1, math.ceil(#words * 12 / 8))
  local bytes = {}
  for index = 1, size do
    bytes[index] = 0
  end
  for _, word in ipairs(words) do
    local position, step = hashes(word, size * 8)
    for _ = 1, 8 do
      local index = math.floor(position / 8) + 1
      bytes[index] = bit.bor(bytes[index], bit.lshift(1, position % 8))
      position = (position + step) % (size * 8)
    end
  end
  for index, byte in ipairs(bytes) do
    bytes[index] = string.char(byte)
  end
  return table.concat(bytes)
end

function M.contains(bytes, word)
  local bits = #bytes * 8
  local position, step = hashes(word, bits)
  for _ = 1, 8 do
    if
      bit.band(
        bytes:byte(math.floor(position / 8) + 1),
        bit.lshift(1, position % 8)
      ) == 0
    then
      return false
    end
    position = (position + step) % bits
  end
  return true
end

return M
