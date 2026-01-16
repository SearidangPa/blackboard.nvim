local M = {}

local sign_namespace

local function get_sign_namespace()
  if not sign_namespace then
    sign_namespace = vim.api.nvim_create_namespace 'blackboard_signs'
  end
  return sign_namespace
end

---@param mark string
---@return number
local function mark_to_id(mark)
  return string.byte(mark)
end

---@param bufnr number
---@param mark string
---@param line number 1-based
function M.place_sign(bufnr, mark, line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ns = get_sign_namespace()

  -- Remove existing sign for this mark first (if any)
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_to_id(mark))

  vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
    sign_text = mark,
    sign_hl_group = 'BlackboardSign',
    id = mark_to_id(mark),
    priority = 10,
  })
end

---@param bufnr number
---@param mark string
function M.remove_sign(bufnr, mark)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ns = get_sign_namespace()
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark_to_id(mark))
end

---@param bufnr number
function M.clear_all_signs(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ns = get_sign_namespace()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---@param bufnr number
function M.refresh_signs_for_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == '' then
    return
  end

  local project_provider = require 'blackboard.bookmarks.providers.project'
  local marks = project_provider.list_marks()

  M.clear_all_signs(bufnr)

  local abs_bufname = vim.fs.normalize(bufname)
  for _, mark_info in ipairs(marks) do
    local abs_filepath = vim.fs.normalize(mark_info.filepath)
    if abs_filepath == abs_bufname then
      M.place_sign(bufnr, mark_info.mark, mark_info.line)
    end
  end
end

function M.refresh_all_signs()
  local project_provider = require 'blackboard.bookmarks.providers.project'
  local marks = project_provider.list_marks()

  -- Group marks by buffer
  ---@type table<number, blackboard.MarkInfo[]>
  local marks_by_buf = {}
  for _, mark_info in ipairs(marks) do
    local bufnr = mark_info.bufnr
    if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
      marks_by_buf[bufnr] = marks_by_buf[bufnr] or {}
      table.insert(marks_by_buf[bufnr], mark_info)
    end
  end

  -- Update each buffer
  for bufnr, buf_marks in pairs(marks_by_buf) do
    M.clear_all_signs(bufnr)
    for _, mark_info in ipairs(buf_marks) do
      M.place_sign(bufnr, mark_info.mark, mark_info.line)
    end
  end
end

function M.setup_autocmds()
  local state = require 'blackboard.state'

  if state.state.sign_autocmd_group then
    vim.api.nvim_del_augroup_by_id(state.state.sign_autocmd_group)
  end

  state.state.sign_autocmd_group = vim.api.nvim_create_augroup('blackboard_signs', { clear = true })

  vim.api.nvim_create_autocmd('BufRead', {
    group = state.state.sign_autocmd_group,
    pattern = '*',
    callback = function(args)
      vim.schedule(function()
        M.refresh_signs_for_buffer(args.buf)
      end)
    end,
  })
end

return M
