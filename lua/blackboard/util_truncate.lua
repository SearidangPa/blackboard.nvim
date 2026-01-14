local M = {}

local default_opts = {
  empty_fallback_len = 8,
  joiner = '_',
  pattern = '[^%s_%-%+%.]+',
}

---@param opts? TruncateMiddleOpts
local function normalize_opts(opts)
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
    empty_fallback_len = opts.empty_fallback_len or default_opts.empty_fallback_len,
    joiner = opts.joiner or default_opts.joiner,
    pattern = opts.pattern or default_opts.pattern,
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

  opts = normalize_opts(opts)

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

return M
