local state = require 'blackboard.state'

local M = {}

local highlight_namespace

local function get_highlight_namespace()
  if not highlight_namespace then
    highlight_namespace = vim.api.nvim_create_namespace 'blackboard'
  end

  return highlight_namespace
end

-- === Truncation Logic ===

local default_truncate_opts = {
  max_do_not_truncate = 16,
  joiner = '_',
  pattern = '[^%s_%-%+%.]+',
  camelcase = false,
  truncate_marker = '-',
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
    empty_fallback_len = opts.empty_fallback_len or default_truncate_opts.max_do_not_truncate,
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

  if #parts <= 4 then
    for i, p in ipairs(parts) do
      parts[i] = p:sub(1, opts.part_len)
    end
    return table.concat(parts, opts.joiner)
  end

  local first = parts[1]:sub(1, opts.part_len)
  local second = parts[2]:sub(1, opts.part_len)
  local second_last = parts[#parts - 1]:sub(1, opts.part_len)
  local last = parts[#parts]:sub(1, opts.part_len)
  return table.concat({ first, second }, opts.joiner) .. opts.truncate_marker .. table.concat({ second_last, last }, opts.joiner)
end

-- === Rendering Logic ===

---@class blackboard.LineTextMeta
---@field bufnr number
---@field line number
---@field filetype string
---@field text string
---@field text_col number Column where line text starts in rendered line

---@class blackboard.ParsedMarks
---@field blackboardLines string[]
---@field functionNames table<number, string>
---@field lineTextMeta table<number, blackboard.LineTextMeta>

---@param str string
---@param max_len number
---@return string
local function truncate_right(str, max_len)
  if type(str) ~= 'string' then
    return ''
  end
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 1) .. '-'
end

---@param marks_info blackboard.MarkInfo[]
---@return blackboard.ParsedMarks
function M.parse_marks_info(marks_info)
  local blackboardLines = {}
  local functionNames = {}
  local lineTextMeta = {}

  if not marks_info or #marks_info == 0 then
    return {
      blackboardLines = { '' },
      functionNames = {},
      lineTextMeta = {},
    }
  end

  local blackboard_state = state.state

  local function format_function_name(func_name)
    -- Strip module/table prefix if present (e.g., "git_push.method" -> "method")
    local method_name = func_name:match '[%.:]([^%.:]+)$' or func_name

    if #method_name <= default_truncate_opts.max_do_not_truncate then
      return method_name
    end

    local joiner = ''
    if method_name:find '_' then
      joiner = '_'
    end

    return M.truncate_middle(method_name, {
      joiner = joiner,
      camelcase = true,
      part_len = 4,
    })
  end

  local entries = {}
  local func_groups = {}

  -- TODO: also show ratio relative to function start and end, if available
  for _, mark_info in ipairs(marks_info) do
    local nearest_func = mark_info.nearest_func or ''
    local has_func = nearest_func ~= ''

    if has_func then
      local key = string.format('%s\0%s', mark_info.filepath or '', nearest_func)
      local group = func_groups[key]
      if not group then
        group = {
          marks = {},
          display_text = format_function_name(nearest_func),
        }
        func_groups[key] = group
        entries[#entries + 1] = {
          kind = 'function',
          group = group,
        }
      end
      group.marks[#group.marks + 1] = {
        mark = mark_info.mark,
        ratio = mark_info.ratio,
      }
    else
      entries[#entries + 1] = {
        kind = 'line',
        mark_info = mark_info,
      }
    end
  end

  for _, entry in ipairs(entries) do
    local currentLine = #blackboardLines + 1

    if entry.kind == 'function' then
      local group = entry.group
      table.sort(group.marks, function(a, b)
        local ratio_a = a.ratio
        local ratio_b = b.ratio
        if ratio_a == nil and ratio_b == nil then
          return a.mark < b.mark
        end
        if ratio_a == nil then
          return false
        end
        if ratio_b == nil then
          return true
        end
        if ratio_a == ratio_b then
          return a.mark < b.mark
        end
        return ratio_a < ratio_b
      end)
      local marks_text = table.concat(
        vim.tbl_map(function(mark_entry)
          return mark_entry.mark
        end, group.marks),
        ' '
      )
      table.insert(blackboardLines, string.format('%s %s', marks_text, group.display_text))
      functionNames[currentLine] = group.display_text
      for _, entry_mark in ipairs(group.marks) do
        blackboard_state.mark_to_line[entry_mark.mark] = currentLine
      end
    else
      local mark_info = entry.mark_info
      local display_text = truncate_right(mark_info.line_text, default_truncate_opts.max_do_not_truncate)
      -- a prefix is 2 characters
      lineTextMeta[currentLine] = {
        bufnr = mark_info.bufnr,
        line = mark_info.line,
        filetype = mark_info.filetype,
        text = mark_info.line_text,
        text_col = 2,
      }
      table.insert(blackboardLines, string.format('%s %s', mark_info.mark, display_text))
      blackboard_state.mark_to_line[mark_info.mark] = currentLine
    end
  end

  return {
    blackboardLines = blackboardLines,
    functionNames = functionNames,
    lineTextMeta = lineTextMeta,
  }
end

-- Treesitter parser/query cache per buffer (keyed by bufnr)
-- Invalidated when buffer changedtick changes
---@type table<number, { parser: any, query: any, tick: number }>
local ts_highlight_cache = {}

---@param bufnr number
---@param filetype string
---@return { parser: any, query: any }?
local function get_cached_ts_data(bufnr, filetype)
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = ts_highlight_cache[bufnr]
  if cached and cached.tick == tick then
    return cached
  end

  local lang = vim.treesitter.language.get_lang(filetype)
  if not lang then
    return nil
  end

  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok_parser or not parser then
    return nil
  end

  local ok_query, query = pcall(vim.treesitter.query.get, lang, 'highlights')
  if not ok_query or not query then
    return nil
  end

  ts_highlight_cache[bufnr] = { parser = parser, query = query, tick = tick }
  return ts_highlight_cache[bufnr]
end

---@param bufnr number
---@param line_row1 number
---@param filetype string
---@return {start_col: number, end_col: number, hl_group: string}[]?
local function get_line_treesitter_highlights(bufnr, line_row1, filetype)
  local ts_data = get_cached_ts_data(bufnr, filetype)
  if not ts_data then
    return nil
  end

  local parser = ts_data.parser
  local query = ts_data.query

  local ok_tree, trees = pcall(function()
    return parser:parse { line_row1 - 1, line_row1 }
  end)
  if not ok_tree or not trees or not trees[1] then
    return nil
  end

  local tree = trees[1]
  local highlights = {}
  local seen = {}

  for id, node in query:iter_captures(tree:root(), bufnr, line_row1 - 1, line_row1) do
    local name = query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()

    if start_row == line_row1 - 1 and end_row == line_row1 - 1 then
      local key = string.format('%d:%d:%s', start_col, end_col, name)
      if not seen[key] then
        seen[key] = true
        table.insert(highlights, {
          start_col = start_col,
          end_col = end_col,
          hl_group = '@' .. name,
        })
      end
    end
  end

  table.sort(highlights, function(a, b)
    return a.start_col < b.start_col
  end)

  return highlights
end

local function set_mark_highlight()
  local ok, theme_loader = pcall(require, 'theme-loader')
  local is_light_mode = ok and theme_loader.cached_is_light_mode or false
  if is_light_mode then
    vim.api.nvim_set_hl(0, 'MarkHighlight', { fg = '#EA9D35' })
  else
    vim.api.nvim_set_hl(0, 'MarkHighlight', { fg = '#f1c232' })
  end
end

set_mark_highlight()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('BlackboardHighlights', { clear = true }),
  callback = set_mark_highlight,
})

---@param parsedMarks blackboard.ParsedMarks
function M.add_highlights(parsedMarks)
  local blackboardLines = parsedMarks.blackboardLines
  local functionNames = parsedMarks.functionNames
  local lineTextMeta = parsedMarks.lineTextMeta

  vim.api.nvim_set_hl(0, 'BlackboardFunctionName', { link = 'Function' })

  local blackboard_state = state.state
  local namespace = get_highlight_namespace()

  for lineIdx, line in ipairs(blackboardLines) do
    local func_name = functionNames and functionNames[lineIdx]
    local marks_prefix
    local func_start -- cache find result to avoid duplicate search

    if func_name then
      func_start = line:find(func_name, 1, true)
      if func_start and func_start > 1 then
        marks_prefix = vim.trim(line:sub(1, func_start - 1))
      end
    else
      marks_prefix = line:match '^([A-Za-z])%s'
    end

    if marks_prefix then
      for idx = 1, #marks_prefix do
        local char = marks_prefix:sub(idx, idx)
        if char:match '[A-Za-z]' then
          vim.api.nvim_buf_set_extmark(blackboard_state.blackboard_buf, namespace, lineIdx - 1, idx - 1, {
            end_col = idx,
            hl_group = 'MarkHighlight',
          })
        end
      end
    end

    -- Reuse cached func_start instead of calling find again
    if func_name and func_start then
      vim.api.nvim_buf_set_extmark(blackboard_state.blackboard_buf, namespace, lineIdx - 1, func_start - 1, {
        end_col = func_start - 1 + #func_name,
        hl_group = 'BlackboardFunctionName',
      })
    end

    local meta = lineTextMeta and lineTextMeta[lineIdx]
    if meta then
      local highlights = get_line_treesitter_highlights(meta.bufnr, meta.line, meta.filetype)
      if highlights then
        local displayed_text = line:sub(meta.text_col + 1)
        local displayed_len = #displayed_text

        -- Get original line from buffer to find leading whitespace
        local original_line = ''
        if vim.api.nvim_buf_is_valid(meta.bufnr) then
          local lines = vim.api.nvim_buf_get_lines(meta.bufnr, meta.line - 1, meta.line, false)
          original_line = lines[1] or ''
        end
        -- Calculate leading whitespace offset
        local trim_offset = #original_line - #vim.trim(original_line)

        for _, hl in ipairs(highlights) do
          -- Adjust for trim offset
          local adj_start = hl.start_col - trim_offset
          local adj_end = hl.end_col - trim_offset

          -- Only apply if within displayed range
          if adj_start < displayed_len and adj_end > 0 then
            adj_start = math.max(adj_start, 0)
            adj_end = math.min(adj_end, displayed_len)

            local buf_start = meta.text_col + adj_start
            local buf_end = meta.text_col + adj_end

            vim.api.nvim_buf_set_extmark(blackboard_state.blackboard_buf, namespace, lineIdx - 1, buf_start, {
              end_col = buf_end,
              hl_group = hl.hl_group,
            })
          end
        end
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
