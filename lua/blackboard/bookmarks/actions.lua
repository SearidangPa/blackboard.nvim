local window = require 'blackboard.ui.window'
local project_provider = require 'blackboard.bookmarks.providers.project'
local config = require 'blackboard.config'

local M = {}

---@param mark string
M.mark = function(mark)
  project_provider.set_mark(mark)
  window.render_blackboard()

  -- Update sign for current buffer
  if config.options.show_signs then
    local signs = require 'blackboard.ui.signs'
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    signs.place_sign(bufnr, mark, pos[1])
  end
end

M.clear_marks = function()
  local marks = nil
  if config.options.show_signs then
    marks = project_provider.list_marks()
  end

  project_provider.clear_marks()
  window.rerender_if_open()

  if config.options.show_signs and marks then
    local signs = require 'blackboard.ui.signs'
    local cleared = {}
    for _, mark_info in ipairs(marks) do
      local bufnr = mark_info.bufnr
      if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) and not cleared[bufnr] then
        cleared[bufnr] = true
        signs.clear_all_signs(bufnr)
      end
    end
  end
end

---@param mark string
M.delete_mark = function(mark)
  -- Capture mark info before deleting (for sign removal)
  local mark_info = nil
  if config.options.show_signs then
    local marks = project_provider.list_marks_lightweight()
    for _, m in ipairs(marks) do
      if m.mark == mark then
        mark_info = m
        break
      end
    end
  end

  project_provider.delete_mark(mark)
  window.rerender_if_open()

  if config.options.show_signs and mark_info and mark_info.bufnr > 0 and vim.api.nvim_buf_is_valid(mark_info.bufnr) then
    local signs = require 'blackboard.ui.signs'
    signs.remove_sign(mark_info.bufnr, mark)
  end
end

---@param mark string
M.jump = function(mark)
  project_provider.jump_to_mark(mark)
  window.render_blackboard()
end

return M
