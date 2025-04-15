local util_mark_info = {}

---@param marks_info blackboard.MarkInfo[]
---@param mark_char string
---@return blackboard.MarkInfo
function util_mark_info.retrieve_mark_info(marks_info, mark_char)
  assert(marks_info, 'No marks info provided')
  assert(mark_char, 'No mark char provided')
  local mark_info
  for _, m in ipairs(marks_info) do
    if m.mark == mark_char then
      mark_info = m
      break
    end
  end
  assert(mark_info, 'No mark info found for mark: ' .. mark_char)
  assert(mark_info.filepath and mark_info.filepath ~= '', 'No filepath found for mark: ' .. mark_char)
  return mark_info
end

---@param all_accessible_marks blackboard.MarkInfo[]
function util_mark_info.group_marks_info_by_filepath(all_accessible_marks)
  local grouped_marks = {}
  for _, m in ipairs(all_accessible_marks) do
    local filepath = m.filepath
    if not grouped_marks[filepath] then
      grouped_marks[filepath] = {}
    end
    table.insert(grouped_marks[filepath], m)
  end

  return grouped_marks
end

---@return blackboard.MarkInfo[]
function util_mark_info.get_accessible_marks_info(show_nearest_func)
  local marks_info = {}
  local cwd = vim.fn.getcwd()
  for char = string.byte 'A', string.byte 'Z' do
    util_mark_info._add_global_mark_info(marks_info, char, cwd, show_nearest_func)
  end
  util_mark_info._add_local_marks(marks_info, show_nearest_func)

  return marks_info
end

---@param blackboard_state blackboard.State
function util_mark_info.get_mark_char(blackboard_state)
  if not vim.api.nvim_buf_is_valid(blackboard_state.blackboard_buf) then
    vim.notify('blackboard buffer is invalid', vim.log.levels.ERROR)
    return ''
  end
  local line_num = vim.fn.line '.'
  local line_text = vim.fn.getline(line_num)

  local mark_char = line_text:match '([A-Z]):' or line_text:match '([a-z]):'
  return mark_char
end

---@return string?
function util_mark_info._nearest_function_at_line(bufnr, line)
  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype) -- Get language from filetype
  local parser = vim.treesitter.get_parser(bufnr, lang)
  assert(parser, 'parser is nil')

  local tree = parser:parse()[1]
  assert(tree, 'tree is nil')

  local root = tree:root()
  assert(root, 'root is nil')

  local function traverse(node)
    local nearest_function = nil
    for child in node:iter_children() do
      if child:type() == 'function_declaration' or child:type() == 'method_declaration' or child:type() == 'function_definition' then
        local start_row, _, end_row, _ = child:range()
        if start_row <= line and end_row >= line then
          for subchild in child:iter_children() do
            if subchild:type() == 'identifier' or subchild:type() == 'name' then
              nearest_function = vim.treesitter.get_node_text(subchild, bufnr)
              break
            end
          end
        end
      end

      if not nearest_function then
        nearest_function = traverse(child)
      end
      if nearest_function then
        break
      end
    end
    return nearest_function
  end

  return traverse(root)
end

---@param marks_info blackboard.MarkInfo[]
function util_mark_info._add_mark_info(marks_info, mark, bufnr, line, col, show_nearest_func)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  ---@diagnostic disable-next-line: undefined-field
  if not vim.uv.fs_stat(filepath) then
    return
  end

  local filetype = require('plenary.filetype').detect_from_extension(filepath)
  vim.bo[bufnr].filetype = filetype

  local nearest_func = show_nearest_func and util_mark_info._nearest_function_at_line(bufnr, line) or nil
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ''
  local filename = vim.fn.fnamemodify(filepath, ':t')
  table.insert(marks_info, {
    mark = mark,
    bufnr = bufnr,
    filename = filename,
    filepath = filepath,
    filetype = filetype,
    line = line,
    col = col,
    nearest_func = nearest_func,
    text = vim.trim(text),
  })
end

---@param marks_info blackboard.MarkInfo[]
function util_mark_info._add_local_marks(marks_info, show_nearest_func)
  local mark_list = vim.fn.getmarklist(vim.api.nvim_get_current_buf())

  for _, mark_entry in ipairs(mark_list) do
    local mark = mark_entry.mark:sub(2, 2)
    if mark:match '[a-z]' then
      local bufnr = mark_entry.pos[1]
      local line = mark_entry.pos[2]
      local col = mark_entry.pos[3]

      if vim.api.nvim_buf_is_valid(bufnr) then
        util_mark_info._add_mark_info(marks_info, mark, bufnr, line, col, show_nearest_func)
      end
    end
  end
end

---@param marks_info blackboard.MarkInfo[]
function util_mark_info._add_global_mark_info(marks_info, char, cwd, show_nearest_func)
  local mark = string.char(char)
  local pos = vim.fn.getpos("'" .. mark)
  if pos[1] == 0 then
    return
  end
  local bufnr = pos[1]
  local line = pos[2]
  local col = pos[3]

  local filepath = vim.fn.bufname(bufnr)
  local abs_filepath = vim.fn.fnamemodify(filepath, ':p')

  if not abs_filepath:find(cwd, 1, true) then
    return
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    util_mark_info._add_mark_info(marks_info, mark, bufnr, line, col, show_nearest_func)
  end
end

return util_mark_info
