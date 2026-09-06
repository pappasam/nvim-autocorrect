local M = {}

-- vim.json.decode overwrites duplicate object keys. Inspect string tokens
-- separately, decoding escapes so equivalent spellings count as duplicates.
local function check_keys(text)
  local seen, pos = {}, 1
  while true do
    local first = text:find('"', pos, true)
    if not first then
      return
    end
    pos = first + 1
    while true do
      pos = assert(text:find('["\\]', pos))
      if text:sub(pos, pos) == '"' then
        break
      end
      pos = pos + 2
    end
    if text:find("^%s*:", pos + 1) then
      local key = vim.json.decode(text:sub(first, pos))
      assert(not seen[key], "Duplicate correction key: " .. key)
      seen[key] = true
    end
    pos = pos + 1
  end
end

function M.load(path)
  local text = table.concat(vim.fn.readfile(path), "\n")
  local groups = vim.json.decode(text)
  assert(text:match("^%s*{"), "Corrections must be a JSON object")
  check_keys(text)
  local entries = {}
  for correction, typos in pairs(groups) do
    assert(
      correction:match("^[a-z]+$"),
      "Corrections must be lowercase ASCII words"
    )
    assert(
      type(typos) == "table" and vim.islist(typos),
      "Typos must be a JSON array"
    )
    assert(#typos > 0, "Typo lists must not be empty: " .. correction)
    for _, typo in ipairs(typos) do
      assert(
        type(typo) == "string" and typo:match("^[a-z]+$"),
        "Typos must be lowercase ASCII words"
      )
      assert(typo ~= correction, "Correction maps to itself: " .. typo)
      assert(not entries[typo], "Duplicate or conflicting typo: " .. typo)
      entries[typo] = correction
    end
  end
  return entries
end

return M
