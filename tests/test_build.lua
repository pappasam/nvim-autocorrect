-- nvim -u NONE --headless -i NONE -l tests/test_build.lua
vim.o.showmode = false
local original = vim.fn.getcwd()
local config = dofile("tests/helpers.lua").fixture()
local source = config .. "/data/corrections.json"
vim.fn.writefile({ '{"the":["teh"],"oldword":["oldtypo"]}' }, source)
local command = {
  vim.v.progpath,
  "-u",
  "NONE",
  "--headless",
  "-i",
  "NONE",
  "-l",
  config .. "/scripts/build-dictionary.lua",
}
local result = vim.system(command, { text = true }):wait()
assert(result.code == 0, result.stderr)
local output = dofile("tests/helpers.lua").output(config)
local target = config .. "/dictionary-target.mpack"
assert(vim.uv.fs_rename(output, target))
assert(vim.uv.fs_symlink(target, output))

-- Match Stow's existing Lua-directory link, without linking the new data/scripts.
vim.fn.mkdir(config .. "/stowed", "p")
assert(vim.uv.fs_symlink(config .. "/lua", config .. "/stowed/lua"))
vim.opt.runtimepath:prepend(config .. "/stowed")
local reader = require("autocorrect.dictionary")
local snapshot = reader.open(output)
local plugin = require("autocorrect")
plugin.setup()
local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end
vim.bo.filetype = "markdown"
feed("ioldtypo <Esc>")
assert(vim.api.nvim_get_current_line() == "oldword ")

local completed = 0
local system = vim.system
vim.system = function(cmd, opts, callback)
  return system(cmd, opts, function(process)
    assert(process.code == 0, process.stderr)
    callback(process)
    vim.schedule(function()
      completed = completed + 1
    end)
  end)
end
vim.cmd.edit({ args = { source }, bang = true })
vim.bo.filetype = "json"
vim.api.nvim_set_current_line('{"the":["teh"],"newword":["newtypo"]}')
vim.cmd.write()
-- Save again while the worker is running: the final source must win.
vim.api.nvim_set_current_line('{"the":["teh"],"latestword":["newtypo"]}')
vim.cmd.write()
assert(
  vim.wait(10000, function()
    return completed == 2
  end, 10),
  "Build timed out"
)
vim.system = system
assert(
  vim.uv.fs_lstat(output).type == "link",
  "Rebuild replaced a Stow symlink"
)
assert(snapshot.lookup("oldtypo") == "oldword", "Existing snapshot changed")
snapshot.close()
vim.cmd.enew({ bang = true })
vim.bo.filetype = "markdown"
feed("inewtypo oldtypo <Esc>")
assert(vim.api.nvim_get_current_line() == "latestword oldtypo ")

table.insert(command, "--check")
result = vim.system(command, { text = true }):wait()
assert(result.code == 0, "Build is not deterministic: " .. result.stderr)
vim.fn.writefile({ '{"changedword":["changedtypo"]}' }, source)
result = vim.system(command, { text = true }):wait()
assert(result.code ~= 0, "Stale generated data went undetected")

-- Every invalid authoring fixture must preserve the generated snapshot.
table.remove(command)
local previous_bytes = vim.fn.readfile(output, "b")
local cases = vim.json.decode(
  table.concat(vim.fn.readfile(original .. "/tests/source_cases.json"), "\n")
)
for _, case in ipairs(cases) do
  if not case.expected then
    vim.fn.writefile({ case.source }, source)
    result = vim.system(command, { text = true }):wait()
    assert(result.code ~= 0, case.name)
    assert(
      vim.deep_equal(previous_bytes, vim.fn.readfile(output, "b")),
      case.name
    )
  end
end
local last_good = reader.open(output)
assert(last_good.lookup("newtypo") == "latestword")
last_good.close()

-- Background errors also leave the editor's loaded dictionary working.
local notify = vim.notify
local failure
vim.notify = function(message, level)
  assert(level == vim.log.levels.ERROR)
  failure = message
end
vim.cmd.AutocorrectBuild()
assert(vim.wait(10000, function()
  return failure ~= nil
end, 10))
vim.notify = notify
feed("onewtypo <Esc>")
assert(vim.api.nvim_get_current_line() == "latestword ")

-- An empty catalog has explicit metadata and installs no abbreviations.
vim.fn.writefile({ "{}" }, source)
result = vim.system(command, { text = true }):wait()
assert(result.code == 0, result.stderr)
local empty = reader.open(output)
assert(empty.count == 0 and empty.max_length == 0)
assert(empty.lookup("newtypo") == nil)
empty.close()
completed = 0
vim.system = function(cmd, opts, callback)
  return system(cmd, opts, function(process)
    assert(process.code == 0, process.stderr)
    callback(process)
    vim.schedule(function()
      completed = completed + 1
    end)
  end)
end
vim.cmd.AutocorrectBuild()
assert(vim.wait(10000, function()
  return completed == 1
end, 10))
vim.system = system
feed("onewtypo <Esc>")
assert(vim.api.nvim_get_current_line() == "newtypo ")
assert(#vim.api.nvim_buf_get_keymap(0, "ia") == 0)
dofile("tests/helpers.lua").cleanup(config)
print(
  "PASS: background rebuilds, queued saves, snapshots, Stow links, stale/invalid data"
)
vim.cmd("qa!")
