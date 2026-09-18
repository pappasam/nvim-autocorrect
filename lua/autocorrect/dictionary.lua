local M = {}

-- Partition by a hash rather than a spelling prefix, so a large family of
-- related typos cannot all end up in the same partition.
function M.bucket(word)
  local hash = 0
  for index = 1, #word do
    hash = (hash * 33 + word:byte(index)) % 256
  end
  return hash + 1
end

function M.open(path)
  local fd = assert(vim.uv.fs_open(path, "r", 438))
  local function read(size, offset)
    local bytes = assert(vim.uv.fs_read(fd, size, offset))
    assert(#bytes == size, "Truncated abbreviation dictionary: " .. path)
    return bytes
  end
  local header_size, header
  local ok, err = pcall(function()
    header_size = assert(tonumber(read(8, 0), 16))
    local size = assert(vim.uv.fs_fstat(fd)).size
    assert(header_size <= size - 8, "Truncated abbreviation header")
    header = vim.mpack.decode(read(header_size, 8))
    assert(header[1] == 4, "Unsupported abbreviation dictionary version")
    assert(type(header[5]) == "string", "Missing dictionary fingerprint")
    local last = header[4][256]
    assert(
      8 + header_size + last[1] + last[2] == size,
      "Truncated abbreviation dictionary"
    )
  end)
  if not ok then
    vim.uv.fs_close(fd)
    error(err)
  end
  local buckets = {}
  local dictionary = {
    count = header[2],
    max_length = header[3],
    fingerprint = header[5],
  }

  function dictionary.lookup(word, correct_capitalized)
    local capitalized = correct_capitalized and word:match("^[A-Z][a-z]+$")
    if capitalized then
      word = word:lower()
    end
    -- All-caps, mixed case, and identifiers remain protected in either mode.
    if not word:match("^[a-z]+$") then
      return nil
    end
    local bucket = M.bucket(word)
    if not buckets[bucket] then
      local location = header[4][bucket]
      local partition =
        vim.mpack.decode(read(location[2], 8 + header_size + location[1]))
      local entries = partition[1]
      local expanded = {}
      for index = 1, #entries, 2 do
        expanded[entries[index]] = entries[index + 1]
      end
      local eligible = {}
      for _, typo in ipairs(partition[2]) do
        eligible[typo] = true
      end
      buckets[bucket] = { expanded, eligible }
    end
    local partition = buckets[bucket]
    local correction = partition[1][word]
    if capitalized then
      if correction and partition[2][word] then
        return correction:sub(1, 1):upper() .. correction:sub(2)
      end
      return nil
    end
    return correction
  end

  function dictionary.close()
    if fd then
      assert(vim.uv.fs_close(fd))
      fd = nil
    end
  end

  return dictionary
end

return M
