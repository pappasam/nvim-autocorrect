local M = {}
local building = false
local pending = false
local context
local cache = require("autocorrect.cache")

local function rebuild()
  if building then
    pending = true
    return
  end
  building = true
  local ok, err = pcall(
    vim.system,
    {
      vim.v.progpath,
      "-u",
      "NONE",
      "--headless",
      "-i",
      "NONE",
      "-l",
      context.root .. "/scripts/build-dictionary.lua",
    },
    { text = true },
    vim.schedule_wrap(function(result)
      building = false
      if pending then
        pending = false
        rebuild()
      elseif result.code ~= 0 then
        vim.notify(result.stderr, vim.log.levels.ERROR)
      else
        local path = cache.current(context.root)
        if path then
          context.reload(path)
        else
          -- A source update or another editor's build raced this worker.
          rebuild()
        end
      end
    end)
  )
  if not ok then
    building = false
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

function M.setup(root, group, reload)
  context = { root = root, reload = reload }
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*/corrections.json",
    callback = function(event)
      if
        vim.uv.fs_realpath(event.file)
        == vim.uv.fs_realpath(root .. "/data/corrections.json")
      then
        rebuild()
      end
    end,
  })
  vim.api.nvim_create_user_command("AutocorrectBuild", rebuild, {
    desc = "Rebuild and reload the autocorrect dictionary",
  })
  local path = cache.current(root)
  if not path and not building then
    rebuild()
  end
  return path
end

return M
