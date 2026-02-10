local config = require 'blackboard.config'
local window = require 'blackboard.ui.window'
local actions = require 'blackboard.bookmarks.actions'
local project_provider = require 'blackboard.bookmarks.providers.project'

local M = {}

-- Timer for debouncing BufWritePost re-renders
local render_timer = nil

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
  -- Debounced to prevent rapid re-renders on frequent saves
  vim.api.nvim_create_user_command('DelMark', function(cmd_opts)
    M.delete_mark(cmd_opts.args)
  end, { nargs = 1 })

  local blackboard_group = vim.api.nvim_create_augroup('blackboard', { clear = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = blackboard_group,
    callback = function()
      if render_timer then
        render_timer:stop()
      end
      render_timer = vim.defer_fn(function()
        window.rerender_if_open()
        render_timer = nil
      end, 100)
    end,
  })
end

M.toggle_mark_window = window.toggle_mark_window
M.mark = actions.mark
M.clear_marks = actions.clear_marks
M.delete_mark = actions.delete_mark
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

return M
