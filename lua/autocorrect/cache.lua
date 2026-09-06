local M = {}

function M.path(root)
  root = assert(vim.uv.fs_realpath(root))
  return vim.fn.stdpath("cache")
    .. "/nvim-autocorrect/"
    .. vim.fn.sha256(root)
    .. ".mpack"
end

-- Stat the inputs rather than reading the entire catalog on every startup.
-- ctime also detects replacements that preserve file size and mtime.
function M.fingerprint(root)
  local inputs = {}
  for _, name in ipairs({
    "data/corrections.json",
    "scripts/build-dictionary.lua",
    "lua/autocorrect/source.lua",
    "lua/autocorrect/dictionary.lua",
    "lua/autocorrect/cache.lua",
  }) do
    local stat = assert(vim.uv.fs_stat(root .. "/" .. name))
    inputs[#inputs + 1] = {
      name,
      stat.size,
      stat.ino,
      stat.mtime.sec,
      stat.mtime.nsec,
      stat.ctime.sec,
      stat.ctime.nsec,
    }
  end
  return vim.fn.sha256(vim.json.encode(inputs))
end

function M.current(root)
  local path = M.path(root)
  local ok, dictionary = pcall(require("autocorrect.dictionary").open, path)
  if not ok then
    return nil
  end
  local success, fingerprint = pcall(M.fingerprint, root)
  dictionary.close()
  if success and dictionary.fingerprint == fingerprint then
    return path
  end
end

return M
