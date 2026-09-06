-- nvim -u NONE --headless -i NONE -l tests/test_cache.lua
vim.o.showmode = false
local helpers = dofile("tests/helpers.lua")
local root = helpers.fixture()
local source = root .. "/data/corrections.json"
vim.fn.writefile({ '{"would":["woudl"]}' }, source)
vim.opt.runtimepath:prepend(root)
local cache = require("autocorrect.cache")
local output = cache.path(root)
assert(cache.current(root) == nil)

-- A read-only checkout needs no installation hook or write access.
local readonly = { root, root .. "/data", source }
for _, path in ipairs(readonly) do
  assert(vim.uv.fs_chmod(path, path == source and 292 or 365))
end
local system = vim.system
local workers, completed = 0, 0
vim.system = function(cmd, opts, callback)
  workers = workers + 1
  return system(cmd, opts, function(result)
    assert(result.code == 0, result.stderr)
    callback(result)
    vim.schedule(function()
      completed = completed + 1
    end)
  end)
end
local plugin = require("autocorrect")
plugin.setup()
plugin.setup()
assert(workers == 1, "Repeated setup started another initial build")
local function type_word(expected)
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = "markdown"
  vim.api.nvim_feedkeys(vim.keycode("iwoudl <Esc>"), "xt", false)
  assert(vim.api.nvim_get_current_line() == expected)
end
type_word("woudl ")
local function wait_for_build(count)
  assert(
    vim.wait(10000, function()
      return completed == count
    end, 10),
    "Automatic build timed out"
  )
  assert(cache.current(root) == output)
end
wait_for_build(1)
type_word("would ")
assert(vim.uv.fs_stat(root .. "/data/dictionary.mpack") == nil)

-- A new editor reuses the disk cache without launching a worker.
local child = [[
vim.opt.runtimepath:prepend(arg[1])
vim.system = function() error("Unexpected rebuild of a current cache") end
require("autocorrect").setup()
vim.bo.filetype = "markdown"
vim.api.nvim_feedkeys(vim.keycode("iwoudl <Esc>"), "xt", false)
assert(vim.api.nvim_get_current_line() == "would ")
]]
local script = vim.fn.tempname() .. ".lua"
vim.fn.writefile(vim.split(child, "\n"), script)
local result = system({
  vim.v.progpath,
  "-u",
  "NONE",
  "--headless",
  "-i",
  "NONE",
  "-l",
  script,
  root,
}, { text = true }):wait()
assert(result.code == 0, result.stderr)
vim.fn.delete(script)
for _, path in ipairs(readonly) do
  assert(vim.uv.fs_chmod(path, path == source and 420 or 493))
end

-- Same-length edits with a restored mtime still invalidate the cache.
local stat = assert(vim.uv.fs_stat(source))
vim.fn.writefile({ '{"could":["woudl"]}' }, source)
assert(
  vim.uv.fs_utime(
    source,
    stat.atime.sec + stat.atime.nsec / 1e9,
    stat.mtime.sec + stat.mtime.nsec / 1e9
  )
)
assert(cache.current(root) == nil)
plugin.setup()
wait_for_build(2)
type_word("could ")

-- Builder updates also invalidate caches, even when the source is unchanged.
local builder = root .. "/scripts/build-dictionary.lua"
vim.fn.writefile({ "-- builder update" }, builder, "a")
assert(cache.current(root) == nil)
plugin.setup()
wait_for_build(3)
type_word("could ")

-- A malformed/truncated cache is rebuilt, without leaking its descriptor.
vim.fn.writefile({ "broken" }, output)
assert(cache.current(root) == nil)
plugin.setup()
wait_for_build(4)
local bytes = table.concat(vim.fn.readfile(output, "b"), "\n")
vim.fn.writefile({ bytes:sub(1, -2) }, output, "b")
assert(cache.current(root) == nil)
plugin.setup()
wait_for_build(5)
type_word("could ")
vim.system = system

-- Failed process creation is reported and can be retried explicitly.
local notification
local notify = vim.notify
vim.notify = function(message)
  notification = message
end
vim.system = function()
  error("Cannot start worker")
end
vim.cmd.AutocorrectBuild()
assert(notification:find("Cannot start worker", 1, true))
vim.system = system
vim.notify = notify
type_word("could ")
helpers.cleanup(root)
print(
  "PASS: automatic builds, cache reuse/invalidation, read-only install, corrupt cache recovery"
)
vim.cmd("qa!")
