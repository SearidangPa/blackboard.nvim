local config = require 'blackboard.config'
local state = require 'blackboard.state'

local M = {}

-- === Truncation Logic ===

local default_truncate_opts = {
  empty_fallback_len = 8,
  joiner = '_',
  pattern = '[^%s_%-%+%.]+',
}

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

  return {
    part_len = part_len,
    no_truncate_max = opts.no_truncate_max or (3 * part_len),
    empty_fallback_len = opts.empty_fallback_len or default_truncate_opts.empty_fallback_len,
    joiner = opts.joiner or default_truncate_opts.joiner,
    pattern = opts.pattern or default_truncate_opts.pattern,
  }
end

---@class TruncateMiddleOpts
---@field part_len number Number of characters to keep from each part.
---@field no_truncate_max? number Maximum length of string to avoid truncation.
---@field empty_fallback_len? number Number of characters to return when input string has no parts.
---@field joiner? string String used to join parts.
---@field pattern? string Lua pattern used to split the string into parts.

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

  local parts = {}
  for p in str:gmatch(opts.pattern) do
    parts[#parts + 1] = p
  end

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
  return table.concat({ first, second_last, last }, opts.joiner)
end

-- === Rendering Logic ===

---@class blackboard.ParsedMarks
---@field blackboardLines string[]
---@field virtualLines string[]

---@param marks_info blackboard.MarkInfo[]
---@return blackboard.ParsedMarks
function M.parse_marks_info(marks_info)
  local blackboardLines = {}
  local virtualLines = {}

  if not marks_info or #marks_info == 0 then
    return {
      blackboardLines = { 'No marks set' },
      virtualLines = { '' },
    }
  end

  local options = config.options
  local blackboard_state = state.state

  for _, mark_info in ipairs(marks_info) do
    local currentLine = #blackboardLines + 1
    local nearest_func = mark_info.nearest_func or ''

    virtualLines[currentLine] = nearest_func

    local symbol = options.not_under_func_symbol
    local func_prefix = ''
    if nearest_func ~= '' then
      symbol = options.under_func_symbol
      func_prefix = '(' .. nearest_func .. ') '
    end

    table.insert(blackboardLines, string.format('%s %s: %s%s', symbol, mark_info.mark, func_prefix, mark_info.text))
    blackboard_state.mark_to_line[mark_info.mark] = currentLine
  end

  return {
    blackboardLines = blackboardLines,
    virtualLines = virtualLines,
  }
end

---@param parsedMarks blackboard.ParsedMarks
function M.add_highlights(parsedMarks)
  local blackboardLines = parsedMarks.blackboardLines
  vim.api.nvim_set_hl(0, 'MarkHighlight', { fg = '#f1c232' })

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
  end
end

---@param parsedMarks blackboard.ParsedMarks
function M.add_virtual_lines(parsedMarks)
  local ns_blackboard = vim.api.nvim_create_namespace 'blackboard_extmarks'
  local blackboard_state = state.state
  vim.api.nvim_buf_clear_namespace(blackboard_state.blackboard_buf, ns_blackboard, 0, -1)

  vim.api.nvim_set_hl(0, 'BlackboardFunctionHeader', { link = 'Function' })

  local last_seen_func = nil

  for line_num, func_name in ipairs(parsedMarks.virtualLines) do
    local extmark_line = line_num - 1
    local func_line = func_name ~= '' and ('❯ ' .. func_name) or ''

    if func_line ~= last_seen_func then
      vim.api.nvim_buf_set_extmark(blackboard_state.blackboard_buf, ns_blackboard, extmark_line, 0, {
        virt_lines = { { { func_line, 'BlackboardFunctionHeader' } } },
        virt_lines_above = true,
        hl_mode = 'combine',
        priority = 10,
      })
    end

    last_seen_func = func_line
  end
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
