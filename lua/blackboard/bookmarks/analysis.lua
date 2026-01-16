local M = {}

---@class blackboard.FunctionContext
---@field func_name string
---@field start_row number 0-based
---@field end_row number 0-based (exclusive)

local query_name = 'blackboard-function'

---@param lang string
---@return vim.treesitter.Query?
local function get_function_query(lang)
  local ok, query = pcall(vim.treesitter.query.get, lang, query_name)
  if ok and query then
    return query
  end
  return nil
end

---@param node_type string
---@return boolean
local function is_function_node_type(node_type)
  return node_type == 'function_declaration'
    or node_type == 'method_declaration'
    or node_type == 'function_definition'
    or node_type == 'function_item'
    or node_type == 'function'
    or node_type == 'method'
end

---@param bufnr number
---@param node any
---@return string
local function get_function_name(bufnr, node)
  local name_fields = node:field 'name'
  if name_fields and name_fields[1] then
    local text = vim.treesitter.get_node_text(name_fields[1], bufnr)
    if text and text ~= '' then
      return text
    end
  end

  for child in node:iter_children() do
    local t = child:type()
    if t == 'identifier' or t == 'name' or t == 'field_identifier' or t == 'property_identifier' then
      local text = vim.treesitter.get_node_text(child, bufnr)
      if text and text ~= '' then
        return text
      end
    end
  end

  return ''
end

---@param root any
---@param cb fun(node: any)
local function walk_nodes(root, cb)
  cb(root)
  for child in root:iter_children() do
    walk_nodes(child, cb)
  end
end

---@param query vim.treesitter.Query
---@param bufnr number
---@param node any
---@return blackboard.FunctionContext?
local function extract_context_from_match(query, bufnr, node)
  local start_row, _, end_row, _ = node:range()
  local func_name = nil

  -- Look for @name capture within this function node
  for id, capture_node in query:iter_captures(node, bufnr) do
    local capture_name = query.captures[id]
    if capture_name == 'name' then
      func_name = vim.treesitter.get_node_text(capture_node, bufnr)
      break
    end
  end

  -- Fallback: try existing get_function_name helper
  if not func_name or func_name == '' then
    func_name = get_function_name(bufnr, node)
  end

  if func_name and func_name ~= '' then
    return {
      func_name = func_name,
      start_row = start_row,
      end_row = end_row,
    }
  end

  return nil
end

---@param bufnr number
---@param row0 number
---@param parser any
---@return blackboard.FunctionContext?
local function enclosing_function_context_fallback(bufnr, row0, parser)
  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local best
  local best_span

  walk_nodes(tree:root(), function(n)
    if not is_function_node_type(n:type()) then
      return
    end

    local start_row, _, end_row, _ = n:range()
    if not (start_row <= row0 and row0 < end_row) then
      return
    end

    local name = get_function_name(bufnr, n)
    if name == '' then
      return
    end

    local span = end_row - start_row
    if not best_span or span < best_span then
      best_span = span
      best = {
        func_name = name,
        start_row = start_row,
        end_row = end_row,
      }
    end
  end)

  return best
end

---@param bufnr number
---@param approx_start_row number
---@param parser any
---@return blackboard.FunctionContext?
local function find_function_by_position_fallback(bufnr, approx_start_row, parser)
  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local best
  local best_score

  walk_nodes(tree:root(), function(n)
    if not is_function_node_type(n:type()) then
      return
    end

    local name = get_function_name(bufnr, n)
    if name == '' then
      return
    end

    local start_row, _, end_row, _ = n:range()
    local score = math.abs(start_row - approx_start_row)

    if not best_score or score < best_score then
      best_score = score
      best = {
        func_name = name,
        start_row = start_row,
        end_row = end_row,
      }
    end
  end)

  return best
end

---@param bufnr number
---@param row0 number
---@param col0 number
---@return blackboard.FunctionContext?
function M.enclosing_function_context(bufnr, row0, col0)
  local ft = vim.bo[bufnr].filetype
  if ft == '' then
    return nil
  end

  local lang = vim.treesitter.language.get_lang(ft)
  if not lang then
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local query = get_function_query(lang)
  if not query then
    -- Fall back to existing behavior if no query file
    return enclosing_function_context_fallback(bufnr, row0, parser)
  end

  local best = nil
  local best_span = nil

  for id, node in query:iter_captures(tree:root(), bufnr) do
    local capture_name = query.captures[id]
    if capture_name == 'function' then
      local start_row, _, end_row, _ = node:range()

      -- Check if cursor is within this function
      if start_row <= row0 and row0 < end_row then
        local span = end_row - start_row
        if not best_span or span < best_span then
          local ctx = extract_context_from_match(query, bufnr, node)
          if ctx then
            best = ctx
            best_span = span
          end
        end
      end
    end
  end

  return best
end

---@param bufnr number
---@param approx_start_row number
---@return blackboard.FunctionContext?
function M.find_function_by_position(bufnr, approx_start_row)
  local ft = vim.bo[bufnr].filetype
  if ft == '' then
    return nil
  end

  local lang = vim.treesitter.language.get_lang(ft)
  if not lang then
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local query = get_function_query(lang)
  if not query then
    return find_function_by_position_fallback(bufnr, approx_start_row, parser)
  end

  local best = nil
  local best_score = nil

  for id, node in query:iter_captures(tree:root(), bufnr) do
    local capture_name = query.captures[id]
    if capture_name == 'function' then
      local ctx = extract_context_from_match(query, bufnr, node)
      if ctx then
        local score = math.abs(ctx.start_row - approx_start_row)
        if not best_score or score < best_score then
          best = ctx
          best_score = score
        end
      end
    end
  end

  return best
end

return M
