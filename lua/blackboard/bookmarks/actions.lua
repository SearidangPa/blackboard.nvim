local window = require 'blackboard.ui.window'
local project_provider = require 'blackboard.bookmarks.providers.project'

local M = {}

---@param mark string
M.mark = function(mark)
  project_provider.set_mark(mark)
  window.render_blackboard()
end

---@param mark string
M.unmark = function(mark)
  project_provider.unset_mark(mark)
  window.rerender_if_open()
end

---@param mark string
M.jump = function(mark)
  project_provider.jump_to_mark(mark)
  window.render_blackboard()
end

return M
