local config = require 'blackboard.config'
local window = require 'blackboard.ui.window'
local actions = require 'blackboard.bookmarks.actions'
local project_provider = require 'blackboard.bookmarks.providers.project'

local M = {}

--- Setup the plugin
---@param opts blackboard.Options
M.setup = function(opts)
  config.setup(opts)

  if
    type(project_provider) ~= 'table'
    or type(project_provider.list_marks) ~= 'function'
    or type(project_provider.set_mark) ~= 'function'
    or type(project_provider.unset_mark) ~= 'function'
    or type(project_provider.jump_to_mark) ~= 'function'
  then
    local message = 'blackboard: project mark provider must implement list_marks/set_mark/unset_mark/jump_to_mark'
    vim.notify(message, vim.log.levels.ERROR)
  end

  -- Setup keybindings
  if config.options.override_vim_m_key then
    -- Override m key to set marks
    vim.keymap.set('n', 'm', function()
      local char = vim.fn.getcharstr()
      if char:match '^[a-z]$' then
        M.mark(char)
      end
    end, { desc = 'Blackboard: Set project mark' })

    -- Bind <leader>b{a-z} to jump to marks
    for i = 0, 25 do
      local letter = string.char(97 + i)
      vim.keymap.set('n', '<Leader>b' .. letter, function()
        M.jump(letter)
      end, { desc = 'Blackboard: Jump to mark ' .. letter })
    end

    -- Toggle window with <leader>B
    vim.keymap.set('n', '<Leader>B', M.toggle_mark_window, { desc = 'Blackboard: Toggle window' })
  else
    -- Default: just toggle binding
    vim.keymap.set('n', '<Leader>bb', M.toggle_mark_window, { desc = 'Blackboard: Toggle window' })
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

return M
