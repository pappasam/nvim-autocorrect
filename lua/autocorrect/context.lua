local M = {}
local markdown = require("autocorrect.markdown")

local function comment_node(node)
  while node do
    local kind = node:type():lower()
    if
      kind == "comment"
      or kind:match("^comment_")
      or kind:match("_comment$")
    then
      return node
    end
    node = node:parent()
  end
end

local function code_block(node)
  while node do
    if
      node:type() == "indented_code_block"
      or node:type() == "fenced_code_block"
    then
      return true
    end
    node = node:parent()
  end
  return false
end

local function tree_context(buf, row, col, is_markdown)
  local parser = vim.treesitter.get_parser(buf)
  if not parser then
    return nil
  end
  -- on_key runs before the separator is inserted; refresh synchronously so
  -- classification includes the word and any delimiters just typed.
  parser:parse()
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col } })
  if not node then
    return nil
  end
  if is_markdown then
    return not code_block(node)
  end
  local comment = comment_node(node)
  if not comment then
    return false
  end
  local first_row, first_col = comment:start()
  -- Consecutive line comments are separate nodes. Include them so fenced
  -- examples and multiline code spans in documentation stay protected.
  while first_row > 0 do
    local previous =
      vim.api.nvim_buf_get_lines(buf, first_row - 1, first_row, false)[1]
    local column = previous:find("%S")
    if not column then
      break
    end
    local prior = comment_node(vim.treesitter.get_node({
      bufnr = buf,
      pos = { first_row - 1, column - 1 },
    }))
    if not prior then
      break
    end
    first_row, first_col = prior:start()
  end
  return true, first_row, first_col
end

local function syntax_context(row, col, is_markdown)
  local comment = false
  for _, id in ipairs(vim.fn.synstack(row + 1, col + 1)) do
    local name = vim.fn.synIDattr(id, "name"):lower()
    local linked = vim.fn.synIDattr(vim.fn.synIDtrans(id), "name"):lower()
    if is_markdown then
      if
        name:match("^markdownurl")
        or name == "markdownautomaticlink"
        or name == "markdownyamlhead"
      then
        return false
      end
    else
      if name:find("string", 1, true) or linked == "string" then
        return false
      end
      comment = comment
        or name:find("comment", 1, true) ~= nil
        or linked == "comment"
    end
  end
  return is_markdown or comment
end

function M.allowed(buf, row, col, end_col, key)
  local ft = vim.bo[buf].filetype
  if ft == "text" or ft == "gitcommit" then
    return true
  end
  if key == "@" then
    return false
  end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local prefix = line:sub(1, end_col)
  local token = (line:sub(1, col):reverse():match("^%S*") or ""):reverse()
    .. (line:sub(col + 1):match("^%S*") or "")
  if
    token:find("://", 1, true)
    or token:match("^www%.")
    or token:find("@", 1, true)
  then
    return false
  end
  local is_markdown = ft == "markdown"
  if is_markdown then
    if
      markdown.protected(buf, row, prefix)
      or prefix:match("%]%([^)]*$")
      or not syntax_context(row, col, true)
    then
      return false
    end
    -- Most prose needs no parse. In particular, reparsing a growing Markdown
    -- paragraph on every separator makes sustained insertion quadratic.
    if not line:match("^    ") and not line:match("^\t") then
      return true
    end
    local ok, allowed = pcall(tree_context, buf, row, col, true)
    -- Without a parser, conservatively treat indentation as code.
    return ok and allowed == true
  end
  local ok, allowed, first_row, first_col =
    pcall(tree_context, buf, row, col, false)
  if not ok or allowed == nil then
    allowed = syntax_context(row, col, false)
    if allowed then
      first_row, first_col = row, col
      while first_col > 0 and syntax_context(row, first_col - 1, false) do
        first_col = first_col - 1
      end
      while first_row > 0 do
        local previous =
          vim.api.nvim_buf_get_lines(buf, first_row - 1, first_row, false)[1]
        local column = previous:find("%S")
        if
          not column or not syntax_context(first_row - 1, column - 1, false)
        then
          break
        end
        first_row = first_row - 1
        first_col = column - 1
      end
    end
  end
  if not allowed then
    return allowed
  end
  local lines =
    vim.api.nvim_buf_get_text(buf, first_row, first_col, row, end_col, {})
  return not markdown.comment_protected(lines)
end

return M
