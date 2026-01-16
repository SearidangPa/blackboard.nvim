local config = require 'blackboard.config'
local window = require 'blackboard.ui.window'
local actions = require 'blackboard.bookmarks.actions'
local project_provider = require 'blackboard.bookmarks.providers.project'

local M = {}

--- Setup the plugin
---@param opts blackboard.Options
M.setup = function(opts)
  config.setup(opts)
  -- Setup sign column marks
  if config.options.show_signs then
    local signs = require 'blackboard.ui.signs'
    signs.setup_autocmds()
  end

  -- Auto-refresh blackboard window on file save (updates function names after LSP rename, etc.)
  local blackboard_group = vim.api.nvim_create_augroup('blackboard', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = blackboard_group,
    callback = function()
      window.rerender_if_open()
    end,
  })
end

M.toggle_mark_window = window.toggle_mark_window
M.mark = actions.mark
M.clear_marks = actions.clear_marks
M.jump = actions.jump

--- Prompt user for a character (a-z) to set a mark
M.prompt_mark = function()
  local char = vim.fn.getcharstr()
  if char:match '^[a-z]$' then
    M.mark(char)
  end
end

--- Load marks into quickfix list
---@param opts? { open?: boolean }
M.to_quickfix = function(opts)
  opts = opts or {}
  local marks = project_provider.list_marks()

  local qf_items = {}
  local MAX_TEXT_LEN = 30
  for _, mark in ipairs(marks) do
    local context
    if mark.nearest_func ~= '' then
      context = string.format('in %s', mark.nearest_func)
    else
      context = mark.line_text:sub(1, MAX_TEXT_LEN)
    end
    qf_items[#qf_items + 1] = {
      filename = mark.filepath,
      lnum = mark.line,
      col = mark.col + 1,
      text = string.format('%s | %s', mark.mark, context),
    }
  end

  vim.fn.setqflist({}, ' ', {
    title = 'Blackboard Marks',
    items = qf_items,
  })

  if opts.open ~= false then
    vim.cmd 'copen'
  end
end

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

vim.api.nvim_create_user_command('BlackboardClear', function()
  M.clear_marks()
end, {
  desc = 'Clear all project marks',
})

vim.api.nvim_create_user_command('BlackboardJump', function(cmd)
  M.jump(cmd.args)
end, {
  desc = 'Jump to project mark (a-z)',
  nargs = 1,
})

vim.api.nvim_create_user_command('BlackboardQuickfix', function()
  M.to_quickfix()
end, {
  desc = 'Load blackboard marks into quickfix',
})

return M
