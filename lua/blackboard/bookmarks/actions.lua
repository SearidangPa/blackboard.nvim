local config = require 'blackboard.config'
local window = require 'blackboard.ui.window'

local M = {}

---@return blackboard.MarkProvider
local function get_provider()
  if config.options.mark_provider then
    return config.options.mark_provider
  end
  return require 'blackboard.bookmarks.providers.project'
end

---@param mark string
M.mark = function(mark)
  local provider = get_provider()
  provider.set_mark(mark)
  window.render_blackboard()
end

---@param mark string
M.unmark = function(mark)
  local provider = get_provider()
  provider.unset_mark(mark)
  window.rerender_if_open()
end

---@param mark string
M.jump = function(mark)
  local provider = get_provider()
  provider.jump_to_mark(mark)
  window.render_blackboard()
end

return M
