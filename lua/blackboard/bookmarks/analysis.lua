local M = {}

---@class blackboard.FunctionContext
---@field func_name string
---@field start_row number 0-based
---@field end_row number 0-based (exclusive)

local query_name = 'blackboard-function'

-- Cached query per language. false means missing for that lang.
---@type table<string, vim.treesitter.Query|false>
local query_cache = {}

-- Cached function contexts per buffer, invalidated by changedtick.
---@type table<number, { tick: number, lang: string, contexts: blackboard.FunctionContext[] }>
local context_cache = {}

---@param lang string
---@return vim.treesitter.Query?
local function get_function_query(lang)
  if query_cache[lang] ~= nil then
    return query_cache[lang] or nil
  end

  local ok, query = pcall(vim.treesitter.query.get, lang, query_name)
  if ok and query then
    query_cache[lang] = query
    return query
  end

  query_cache[lang] = false
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
---@param cb fun(node: any): boolean?
---@return boolean
local function walk_nodes(root, cb)
  if cb(root) then
    return true
  end
  for child in root:iter_children() do
    if walk_nodes(child, cb) then
      return true
    end
  end
  return false
end

---@param query vim.treesitter.Query
---@param bufnr number
---@param root any
---@return blackboard.FunctionContext[]
local function build_function_contexts(query, bufnr, root)
  local contexts = {}
  local by_range = {}

  for _, match in query:iter_matches(root, bufnr) do
    local func_node = nil
    local name_node = nil

    if type(match) ~= 'table' then
      goto continue
    end

    for id, node in pairs(match) do
      local capture_name = query.captures[id]
      if type(node) == 'table' then
        node = node[1]
      end
      if not node then
        goto continue
      end
      if capture_name == 'function' then
        func_node = node
      elseif capture_name == 'name' then
        name_node = node
      end
    end

    if func_node then
      local func_name = ''
      if name_node then
        func_name = vim.treesitter.get_node_text(name_node, bufnr)
      end

      if not func_name or func_name == '' then
        func_name = get_function_name(bufnr, func_node)
      end

      if func_name and func_name ~= '' then
        local start_row, _, end_row, _ = func_node:range()
        local key = string.format('%d:%d', start_row, end_row)
        if not by_range[key] then
          by_range[key] = true
          table.insert(contexts, {
            func_name = func_name,
            start_row = start_row,
            end_row = end_row,
          })
        end
      end
    end
    ::continue::
  end

  return contexts
end

---@param bufnr number
---@param lang string
---@param parser any
---@param query vim.treesitter.Query
---@return blackboard.FunctionContext[]?
local function get_cached_function_contexts(bufnr, lang, parser, query)
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = context_cache[bufnr]
  if cached and cached.tick == tick and cached.lang == lang then
    return cached.contexts
  end

  local ok_tree, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_tree or not trees or not trees[1] then
    return nil
  end

  local root = trees[1]:root()
  local contexts = build_function_contexts(query, bufnr, root)
  context_cache[bufnr] = { tick = tick, lang = lang, contexts = contexts }
  return contexts
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
      return false
    end

    local start_row, _, end_row, _ = n:range()
    if not (start_row <= row0 and row0 < end_row) then
      return false
    end

    local name = get_function_name(bufnr, n)
    if name == '' then
      return false
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
    return false
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
      return false
    end

    local name = get_function_name(bufnr, n)
    if name == '' then
      return false
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
      -- Early exit if we found exact match
      if score == 0 then
        return true
      end
    end
    return false
  end)

  return best
end

---@param bufnr number
---@param row0 number
---@param _col0 number
---@return blackboard.FunctionContext?
function M.enclosing_function_context(bufnr, row0, _col0)
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

  local query = get_function_query(lang)
  if not query then
    -- Fall back to existing behavior if no query file
    return enclosing_function_context_fallback(bufnr, row0, parser)
  end

  local contexts = get_cached_function_contexts(bufnr, lang, parser, query)
  if not contexts then
    return nil
  end

  local best = nil
  local best_span = nil

  for _, ctx in ipairs(contexts) do
    if ctx.start_row <= row0 and row0 < ctx.end_row then
      local span = ctx.end_row - ctx.start_row
      if not best_span or span < best_span then
        best = ctx
        best_span = span
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

  local query = get_function_query(lang)
  if not query then
    return find_function_by_position_fallback(bufnr, approx_start_row, parser)
  end

  local contexts = get_cached_function_contexts(bufnr, lang, parser, query)
  if not contexts then
    return nil
  end

  local best = nil
  local best_score = nil

  for _, ctx in ipairs(contexts) do
    local score = math.abs(ctx.start_row - approx_start_row)
    if not best_score or score < best_score then
      best = ctx
      best_score = score
    end
  end

  return best
end

return M
