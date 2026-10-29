local M = {}
local buffers = {}

local function escaped(line, index)
  local first = index - 1
  while line:byte(first) == 92 do
    first = first - 1
  end
  return (index - first - 1) % 2 == 1
end

-- Keep incomplete code spans protected while typing. Parsers generally only
-- recognize inline code once its closing backticks have been entered.
local function advance(state, line, markup)
  local fence, ticks = state.fence, state.ticks
  local tag, quote = state.tag, state.quote
  local body = line:gsub("^%s*", "")
  local quotes = 0
  while body:match("^>") do
    quotes = quotes + 1
    body = body:gsub("^>%s*", "")
  end
  if fence and quotes < state.quotes then
    fence, ticks = nil, 0
  end
  body = body:gsub("^[-+*]%s+", ""):gsub("^%d+[.)]%s+", "")
  local run = body:match("^(````*)") or body:match("^(~~~~*)")
  if fence then
    if
      run
      and run:sub(1, 1) == fence:sub(1, 1)
      and #run >= #fence
      and body:sub(#run + 1):match("^%s*$")
    then
      return { ticks = 0 }, true
    end
    return state, true, true
  end
  if
    ticks == 0
    and not tag
    and run
    and (run:sub(1, 1) ~= "`" or not body:sub(#run + 1):find("`", 1, true))
  then
    return { fence = run, ticks = 0, quotes = quotes }, true
  end
  if not tag and line:match("^%s*$") then
    return { ticks = 0 }, false
  end
  local pos = 1
  while true do
    local first = line:find(markup and "[`<>\"']" or "`", pos)
    if not first then
      break
    end
    local char = line:sub(first, first)
    pos = first + 1
    if tag then
      if quote then
        if char == quote then
          quote = nil
        end
      elseif char == '"' or char == "'" then
        quote = char
      elseif char == ">" then
        tag = nil
      end
    elseif char == "`" then
      local _, last = line:find("`+", first)
      if ticks > 0 or not escaped(line, first) then
        local length = last - first + 1
        if ticks == 0 then
          ticks = length
        elseif ticks == length then
          ticks = 0
        end
      end
      pos = last + 1
    elseif ticks == 0 and char == "<" then
      if
        not escaped(line, first)
        and line:sub(first, first + 2):match("^</?[A-Za-z]")
      then
        tag = true
      end
    end
  end
  return { ticks = ticks, tag = tag, quote = quote }, ticks > 0 or tag == true
end

local function document(state, line, row, structured)
  -- Metadata is protected as a block, including incomplete YAML while typing.
  -- Only a delimiter at the start of a Markdown document opens frontmatter.
  if
    structured
    and row == 0
    and line:gsub("^\239\187\191", ""):match("^%-%-%-%s*$")
  then
    return { ticks = 0, frontmatter = true }, true
  end
  if state.frontmatter then
    local closing = line:match("^%-%-%-%s*$") or line:match("^%.%.%.%s*$")
    return { ticks = 0, frontmatter = not closing }, true
  end
  local next_state, protected, fenced = advance(state, line, structured)
  if structured and not state.fence and state.ticks == 0 and not state.tag then
    local body = line:gsub("^%s*", "")
    while body:match("^>") do
      body = body:gsub("^>%s*", "")
    end
    local label, destination = body:match("^%[([^%]]+)%]:%s*(.*)$")
    if label and label:sub(1, 1) ~= "^" then
      next_state.reference = destination == ""
    elseif state.reference then
      destination = body
    end
    if destination and (not label or label:sub(1, 1) ~= "^") then
      -- The title after a destination is prose; the destination itself is not.
      protected = protected
        or destination:match("^%S*$") ~= nil
        or destination:match("^<[^>]*$") ~= nil
    end
  end
  return next_state, protected, fenced
end

function M.protected(buf, row, prefix)
  local states = buffers[buf]
  if not states then
    states = {}
    buffers[buf] = states
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first)
        for index = #states, first + 1, -1 do
          states[index] = nil
        end
      end,
      on_reload = function()
        for index = #states, 1, -1 do
          states[index] = nil
        end
      end,
      on_detach = function()
        buffers[buf] = nil
      end,
    })
  end
  local ft = vim.bo[buf].filetype
  if states.filetype ~= ft then
    for index = #states, 1, -1 do
      states[index] = nil
    end
    states.filetype = ft
  end
  local structured = ft == "markdown"
  local state = states[math.min(row, #states)] or { ticks = 0 }
  if #states < row then
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, #states, row, false)) do
      state = document(state, line, #states, structured)
      states[#states + 1] = state
    end
  end
  local _, protected, fenced_content = document(state, prefix, row, structured)
  return protected, fenced_content == true
end

function M.comment_protected(lines)
  local state, protected = { ticks = 0 }, false
  for _, line in ipairs(lines) do
    -- Strip common documentation-comment leaders before looking for fences.
    while line:match("^%s*>") do
      line = line:gsub("^%s*>%s?", "")
    end
    line = line:gsub("^%s*[/#!*%-]+%s?", "")
    state, protected = advance(state, line)
  end
  return protected
end

return M
