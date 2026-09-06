local M = {}

local enabled_filetypes = { gitcommit = true, markdown = true }
local namespace = vim.api.nvim_create_namespace("NvimAutocorrect")
local keyword = vim.regex([[^\k$]])
local preceding_word = vim.regex([[\k\+$]])
local following_keyword = vim.regex([[^\k]])
local seed = "__autocorrect__"
local dictionary
local dictionary_path
local buffer
local installed = {}
local config = vim.fs.dirname(
  vim.fs.dirname(
    vim.fs.dirname(
      assert(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
    )
  )
)

local function clear(keep_seed)
  for typo in pairs(installed) do
    if not keep_seed or typo ~= seed then
      if vim.api.nvim_buf_is_valid(buffer) then
        -- A user command may already have cleared the abbreviation.
        pcall(vim.keymap.del, "ia", typo, { buffer = buffer })
      end
      installed[typo] = nil
    end
  end
end

local function stop()
  vim.on_key(nil, namespace)
  clear(false)
  buffer = nil
end

local function install(typo, correction)
  if installed[typo] or next(vim.fn.maparg(typo, "i", true, true)) then
    return
  end
  vim.keymap.set("ia", typo, correction, { buffer = buffer })
  installed[typo] = true
end

local function inserting_prose()
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  return (mode == "i" or mode == "R")
    and enabled_filetypes[vim.bo.filetype] == true
end

local function on_key(key)
  -- Ctrl-C can leave Insert mode without firing InsertLeave.
  if
    key == "\003"
    or buffer ~= vim.api.nvim_get_current_buf()
    or not inserting_prose()
  then
    stop()
    return
  end
  if keyword:match_str(key) then
    return
  end

  clear(true)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  -- Read one extra byte so a longer word cannot be mistaken for a matching
  -- suffix. Never correct a substring inside a name, word, or identifier.
  local start_col = math.max(0, col - dictionary.max_length - 1)
  local text = vim.api.nvim_buf_get_text(
    buffer,
    row,
    start_col,
    row,
    math.min(col + 4, vim.fn.col("$") - 1),
    {}
  )[1]
  -- Escape and Ctrl-] do not insert a separator; do not expand a prefix of the
  -- word to the right. A typed separator establishes a new word boundary.
  if
    (key == "\027" or key == "\029")
    and following_keyword:match_str(text:sub(col - start_col + 1))
  then
    return
  end
  text = text:sub(1, col - start_col)
  local first, last = preceding_word:match_str(text)
  local word = first and text:sub(first + 1, last) or ""
  if #word > dictionary.max_length then
    return
  end
  local correction = dictionary.lookup(word)
  if correction then
    install(word, correction)
  end
end

local function start()
  stop()
  if not enabled_filetypes[vim.bo.filetype] then
    return
  end
  if not dictionary and not dictionary_path then
    return
  end
  dictionary = dictionary
    or require("autocorrect.dictionary").open(dictionary_path)
  if dictionary.count == 0 then
    return
  end
  buffer = vim.api.nvim_get_current_buf()
  -- Neovim can skip abbreviation checks if none exist before reading input.
  -- An identity abbreviation enables checks without bypassing our word/case
  -- guards. Only one actual correction is installed at a time.
  install(seed, seed)
  vim.on_key(on_key, namespace)
end

local function reload(path)
  stop()
  dictionary_path = path
  if dictionary then
    dictionary.close()
    dictionary = nil
  end
  if inserting_prose() then
    start()
  end
end

function M.setup(opts)
  opts = opts or {}
  local filetypes = opts.filetypes or { "gitcommit", "markdown" }
  assert(type(filetypes) == "table", "autocorrect.filetypes must be a list")
  local enabled = {}
  for _, filetype in ipairs(filetypes) do
    assert(
      type(filetype) == "string",
      "autocorrect.filetypes entries must be strings"
    )
    enabled[filetype] = true
  end
  stop()
  enabled_filetypes = enabled
  vim.g.loaded_nvim_autocorrect = true
  local group =
    vim.api.nvim_create_augroup("NvimAutocorrect", { clear = true })
  vim.api.nvim_create_autocmd(
    "InsertEnter",
    { group = group, callback = start }
  )
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "BufWipeout" }, {
    group = group,
    callback = function(event)
      if event.buf == buffer then
        stop()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group = group,
    callback = function()
      if inserting_prose() then
        start()
      else
        stop()
      end
    end,
  })
  dictionary_path =
    require("autocorrect.maintenance").setup(config, group, reload)
  if inserting_prose() then
    start()
  end
end

return M
