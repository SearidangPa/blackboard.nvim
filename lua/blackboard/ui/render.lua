local state = require 'blackboard.state'

local M = {}

-- === Truncation Logic ===

local default_truncate_opts = {
  empty_fallback_len = 8,
  joiner = '_',
  pattern = '[^%s_%-%+%.]+',
  camelcase = false,
  truncate_marker = '…',
}

local function split_on_pattern(str, pattern)
  local parts = {}
  for p in str:gmatch(pattern) do
    parts[#parts + 1] = p
  end
  return parts
end

local function split_camelcase(str)
  if not (str:match '%u' and str:match '%l') then
    return { str }
  end

  local parts = {}
  local current = ''
  local prev = ''

  for i = 1, #str do
    local char = str:sub(i, i)
    local next_char = str:sub(i + 1, i + 1)
    local split_before = char:match '%u' and (prev:match '%l' or (next_char ~= '' and next_char:match '%l'))

    if split_before and current ~= '' then
      parts[#parts + 1] = current
      current = char
    else
      current = current .. char
    end

    prev = char
  end

  if current ~= '' then
    parts[#parts + 1] = current
  end

  return parts
end

---@param str string
---@param opts TruncateMiddleOpts
---@return string[]
local function split_parts(str, opts)
  local parts = split_on_pattern(str, opts.pattern)
  if #parts <= 1 and opts.camelcase then
    return split_camelcase(str)
  end
  return parts
end

---@param opts? TruncateMiddleOpts
local function normalize_truncate_opts(opts)
  opts = opts or {}

  local part_len = opts.part_len
  if part_len == nil then
    part_len = 3
    if vim.fn.has 'win32' ~= 1 then
      part_len = 4
    end
  end

  local joiner = opts.joiner
  if joiner == nil then
    joiner = default_truncate_opts.joiner
  end

  local pattern = opts.pattern
  if pattern == nil then
    pattern = default_truncate_opts.pattern
  end

  local camelcase = opts.camelcase
  if camelcase == nil then
    camelcase = default_truncate_opts.camelcase
  end

  local truncate_marker = opts.truncate_marker
  if truncate_marker == nil then
    truncate_marker = default_truncate_opts.truncate_marker
  end

  return {
    part_len = part_len,
    no_truncate_max = opts.no_truncate_max or (3 * part_len),
    empty_fallback_len = opts.empty_fallback_len or default_truncate_opts.empty_fallback_len,
    joiner = joiner,
    pattern = pattern,
    camelcase = camelcase,
    truncate_marker = truncate_marker,
  }
end

---@class TruncateMiddleOpts
---@field part_len number Number of characters to keep from each part.
---@field no_truncate_max? number Maximum length of string to avoid truncation.
---@field empty_fallback_len? number Number of characters to return when input string has no parts.
---@field joiner? string String used to join parts.
---@field pattern? string Lua pattern used to split the string into parts.
---@field camelcase? boolean Split camelCase into parts when no separators.
---@field truncate_marker? string Marker inserted when middle is collapsed.

---@param str string Input string to truncate.
---@param opts? TruncateMiddleOpts Options for truncation.
function M.truncate_middle(str, opts)
  if type(str) ~= 'string' then
    return ''
  end

  opts = normalize_truncate_opts(opts)

  if #str <= opts.no_truncate_max then
    return str
  end

  local parts = split_parts(str, opts)

  if #parts == 0 then
    return str:sub(1, opts.empty_fallback_len)
  end

  if #parts <= 3 then
    for i, p in ipairs(parts) do
      parts[i] = p:sub(1, opts.part_len)
    end
    return table.concat(parts, opts.joiner)
  end

  local first = parts[1]:sub(1, opts.part_len)
  local second_last = parts[#parts - 1]:sub(1, opts.part_len)
  local last = parts[#parts]:sub(1, opts.part_len)
  return table.concat({ first, opts.truncate_marker, second_last, last }, opts.joiner)
end

-- === Rendering Logic ===

---@class blackboard.ParsedMarks
---@field blackboardLines string[]
---@field functionNames string[]

local function truncate_function_name(name)
  local joiner = name:match '[%s_%-%+%.]' and '_' or ''
  return M.truncate_middle(name, {
    joiner = joiner,
    camelcase = true,
  })
end

local function truncate_line_text(text)
  return M.truncate_middle(text, {
    no_truncate_max = 20,
    part_len = 3,
    joiner = '_',
    camelcase = false,
  })
end

---@param marks_info blackboard.MarkInfo[]
---@return blackboard.ParsedMarks
function M.parse_marks_info(marks_info)
  local blackboardLines = {}
  local functionNames = {}

  if not marks_info or #marks_info == 0 then
    return {
      blackboardLines = { 'No marks set' },
      functionNames = {},
    }
  end

  local blackboard_state = state.state

  for _, mark_info in ipairs(marks_info) do
    local currentLine = #blackboardLines + 1
    local nearest_func = mark_info.nearest_func or ''
    local line_text = nearest_func ~= '' and truncate_function_name(nearest_func) or truncate_line_text(mark_info.text)

    if nearest_func ~= '' then
      functionNames[currentLine] = line_text
    end

    table.insert(blackboardLines, string.format('%s: %s', mark_info.mark, line_text))
    blackboard_state.mark_to_line[mark_info.mark] = currentLine
  end

  return {
    blackboardLines = blackboardLines,
    functionNames = functionNames,
  }
end

---@param parsedMarks blackboard.ParsedMarks
function M.add_highlights(parsedMarks)
  local blackboardLines = parsedMarks.blackboardLines
  local functionNames = parsedMarks.functionNames
  vim.api.nvim_set_hl(0, 'MarkHighlight', { fg = '#f1c232' })
  vim.api.nvim_set_hl(0, 'BlackboardFunctionName', { link = 'Function' })

  local blackboard_state = state.state

  for lineIdx, line in ipairs(blackboardLines) do
    local markMatch = line:match '([A-Za-z]):'
    if markMatch then
      local endCol = line:find(markMatch .. ':')
      if endCol then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(blackboard_state.blackboard_buf, -1, 'MarkHighlight', lineIdx - 1, endCol - 1, endCol)
      end
    end

    local func_name = functionNames and functionNames[lineIdx]
    if func_name then
      local start_col = line:find(func_name, 1, true)
      if start_col then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(blackboard_state.blackboard_buf, -1, 'BlackboardFunctionName', lineIdx - 1, start_col - 1, start_col - 1 + #func_name)
      end
    end
  end
end

---@param parsed_marks_info blackboard.ParsedMarks
---@return number
function M.desired_width(parsed_marks_info)
  local max_width = 0
  for _, line in ipairs(parsed_marks_info.blackboardLines) do
    local width = vim.fn.strdisplaywidth(line)
    if width > max_width then
      max_width = width
    end
  end

  if max_width == 0 then
    max_width = 1
  end

  local max_allowed = math.max(vim.o.columns - 2, 1)
  return math.min(max_width, max_allowed)
end

---@param parsed_marks_info blackboard.ParsedMarks
---@return number
function M.desired_height(parsed_marks_info)
  local height = #parsed_marks_info.blackboardLines
  if height == 0 then
    height = 1
  end

  local max_height = math.floor(vim.o.lines * 0.8)
  if height > max_height then
    height = max_height
  end

  return height
end

return M
