local M = {}

function M.fixture()
  local root = vim.fn.getcwd()
  local path = vim.fn.tempname()
  for _, directory in ipairs({ "lua/autocorrect", "scripts", "data" }) do
    vim.fn.mkdir(path .. "/" .. directory, "p")
  end
  for _, file in ipairs({
    "lua/autocorrect/init.lua",
    "lua/autocorrect/dictionary.lua",
    "lua/autocorrect/source.lua",
    "lua/autocorrect/maintenance.lua",
    "lua/autocorrect/cache.lua",
    "scripts/build-dictionary.lua",
  }) do
    assert(vim.uv.fs_copyfile(root .. "/" .. file, path .. "/" .. file))
  end
  return path
end

function M.output(root)
  return dofile(root .. "/lua/autocorrect/cache.lua").path(root)
end

function M.cleanup(root)
  vim.fn.delete(M.output(root))
  vim.fn.delete(root, "rf")
end

return M
