local util_mark_info = {}

---@class blackboard.FunctionContext
---@field func_name string
---@field start_row number 0-based
---@field end_row number 0-based (exclusive)

local function get_parser(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == '' then
    return nil
  end

  local lang = vim.treesitter.language.get_lang(ft)
  return vim.treesitter.get_parser(bufnr, lang)
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

---@param bufnr number
---@param row0 number
---@param col0 number
---@return blackboard.FunctionContext?
function util_mark_info.enclosing_function_context(bufnr, row0, col0)
  local parser = get_parser(bufnr)
  if not parser then
    return nil
  end

  local node = vim.treesitter.get_node {
    bufnr = bufnr,
    pos = { row0, col0 },
  }

  if node then
    local cur = node
    while cur do
      if is_function_node_type(cur:type()) then
        local name = get_function_name(bufnr, cur)
        if name ~= '' then
          local start_row, _, end_row, _ = cur:range()
          return {
            func_name = name,
            start_row = start_row,
            end_row = end_row,
          }
        end
      end
      cur = cur:parent()
    end
  end

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
---@return blackboard.FunctionContext?
function util_mark_info.find_function_by_position(bufnr, approx_start_row)
  local parser = get_parser(bufnr)
  if not parser then
    return nil
  end

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

return util_mark_info
