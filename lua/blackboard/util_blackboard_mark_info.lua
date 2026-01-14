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

  local ok_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
  if not ok_lang or not lang then
    return nil
  end

  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok_parser then
    return nil
  end

  return parser
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
  for child in node:iter_children() do
    local t = child:type()
    if t == 'identifier' or t == 'name' then
      local ok_text, text = pcall(vim.treesitter.get_node_text, child, bufnr)
      if ok_text and text and text ~= '' then
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

  local ok_node, node = pcall(vim.treesitter.get_node, {
    bufnr = bufnr,
    pos = { row0, col0 },
  })

  if ok_node and node then
    local cur = node
    while cur do
      if is_function_node_type(cur:type()) then
        local start_row, _, end_row, _ = cur:range()
        return {
          func_name = get_function_name(bufnr, cur),
          start_row = start_row,
          end_row = end_row,
        }
      end
      cur = cur:parent()
    end
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local found
  walk_nodes(tree:root(), function(n)
    if found then
      return
    end

    if not is_function_node_type(n:type()) then
      return
    end

    local start_row, _, end_row, _ = n:range()
    if start_row <= row0 and row0 < end_row then
      found = {
        func_name = get_function_name(bufnr, n),
        start_row = start_row,
        end_row = end_row,
      }
    end
  end)

  return found
end

---@param bufnr number
---@param func_name string
---@param approx_start_row number
---@return blackboard.FunctionContext?
function util_mark_info.find_function_by_name(bufnr, func_name, approx_start_row)
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
    if name ~= func_name then
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
