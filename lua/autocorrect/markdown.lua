local M = {}
local buffers = {}

-- Keep incomplete code spans protected while typing. Parsers generally only
-- recognize inline code once its closing backticks have been entered.
local function advance(state, line)
  local fence, ticks = state.fence, state.ticks
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
    return state, true
  end
  if
    ticks == 0
    and run
    and (run:sub(1, 1) ~= "`" or not body:sub(#run + 1):find("`", 1, true))
  then
    return { fence = run, ticks = 0, quotes = quotes }, true
  end
  if line:match("^%s*$") then
    return { ticks = 0 }, false
  end
  local pos = 1
  while true do
    local first, last = line:find("`+", pos)
    if not first then
      break
    end
    local escaped = false
    if ticks == 0 then
      local backslashes = line:sub(1, first - 1):match("\\*$")
      escaped = #backslashes % 2 == 1
    end
    if not escaped then
      local length = last - first + 1
      if ticks == 0 then
        ticks = length
      elseif ticks == length then
        ticks = 0
      end
    end
    pos = last + 1
  end
  return { ticks = ticks }, ticks > 0
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
  local state = states[math.min(row, #states)] or { ticks = 0 }
  if #states < row then
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, #states, row, false)) do
      state = advance(state, line)
      states[#states + 1] = state
    end
  end
  local _, protected = advance(state, prefix)
  return protected
end

function M.comment_protected(lines)
  local state, protected = { ticks = 0 }, false
  for _, line in ipairs(lines) do
    -- Strip common documentation-comment leaders before looking for fences.
    line = line:gsub("^%s*[/#!*%-]+%s?", "")
    state, protected = advance(state, line)
  end
  return protected
end

return M
