local config = require 'blackboard.config'
local window = require 'blackboard.ui.window'
local actions = require 'blackboard.bookmarks.actions'

local M = {}

---@param msg string
local function notify_err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

---@return blackboard.MarkProvider
local function get_provider()
  if config.options.mark_provider then
    return config.options.mark_provider
  end
  return require 'blackboard.bookmarks.providers.project'
end

--- Setup the plugin
---@param opts blackboard.Options
M.setup = function(opts)
  config.setup(opts)

  local provider = get_provider()
  if
    type(provider) ~= 'table'
    or type(provider.list_marks) ~= 'function'
    or type(provider.set_mark) ~= 'function'
    or type(provider.unset_mark) ~= 'function'
    or type(provider.jump_to_mark) ~= 'function'
  then
    notify_err 'blackboard: mark_provider must implement list_marks/set_mark/unset_mark/jump_to_mark'
  end
end

M.toggle_mark_window = window.toggle_mark_window
M.mark = actions.mark
M.unmark = actions.unmark
M.jump = actions.jump

vim.api.nvim_create_user_command('BlackboardToggle', M.toggle_mark_window, {
  desc = 'Toggle Blackboard',
})

vim.api.nvim_create_user_command('BlackboardMark', function(cmd)
  M.mark(cmd.args)
end, {
  desc = 'Set project mark (a-z)',
  nargs = 1,
})

vim.api.nvim_create_user_command('BlackboardUnmark', function(cmd)
  M.unmark(cmd.args)
end, {
  desc = 'Unset project mark (a-z)',
  nargs = 1,
})

vim.api.nvim_create_user_command('BlackboardJump', function(cmd)
  M.jump(cmd.args)
end, {
  desc = 'Jump to project mark (a-z)',
  nargs = 1,
})

vim.keymap.set('n', '<Leader>bb', M.toggle_mark_window, { desc = 'Toggle Blackboard' })

return M
