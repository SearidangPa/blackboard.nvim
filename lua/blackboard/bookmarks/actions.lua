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

---@param mark string
M.unmark = function(mark)
  -- Get mark info before removal to know which buffer to update
  local mark_info = nil
  if config.options.show_signs then
    local marks = project_provider.list_marks()
    for _, m in ipairs(marks) do
      if m.mark == mark then
        mark_info = m
        break
      end
    end
  end

  project_provider.unset_mark(mark)
  window.rerender_if_open()

  -- Remove sign
  if config.options.show_signs and mark_info and mark_info.bufnr > 0 then
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
