local M = {}

local signs_defined = false

local function define_highlight()
  vim.api.nvim_set_hl(0, 'BlackboardSign', { fg = '#f1c232' })
end

local function ensure_signs_defined()
  if signs_defined then
    return
  end

  define_highlight()

  -- Re-apply highlight after colorscheme changes
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('blackboard_sign_hl', { clear = true }),
    callback = define_highlight,
  })

  -- Define signs for each letter a-z
  for i = 0, 25 do
    local letter = string.char(97 + i)
    vim.fn.sign_define('BlackboardMark_' .. letter, {
      text = letter,
      texthl = 'BlackboardSign',
    })
  end
  signs_defined = true
end

---@param bufnr number
---@param mark string
---@param line number 1-based
function M.place_sign(bufnr, mark, line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  ensure_signs_defined()

  -- Remove existing sign for this mark first
  vim.fn.sign_unplace('blackboard_signs', { buffer = bufnr, id = string.byte(mark) })

  -- Place new sign
  vim.fn.sign_place(string.byte(mark), 'blackboard_signs', 'BlackboardMark_' .. mark, bufnr, {
    lnum = line,
    priority = 10,
  })
end

---@param bufnr number
---@param mark string
function M.remove_sign(bufnr, mark)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.fn.sign_unplace('blackboard_signs', { buffer = bufnr, id = string.byte(mark) })
end

---@param bufnr number
function M.clear_all_signs(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.fn.sign_unplace('blackboard_signs', { buffer = bufnr })
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
