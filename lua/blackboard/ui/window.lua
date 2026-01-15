local config = require 'blackboard.config'
local state = require 'blackboard.state'
local render = require 'blackboard.ui.render'

local M = {}

---@return blackboard.MarkProvider
local function get_provider()
  if config.options.mark_provider then
    return config.options.mark_provider
  end
  return require 'blackboard.bookmarks.providers.project'
end

function M.render_blackboard()
  local provider = get_provider()
  local marks_info = provider.list_marks()
  local blackboard_state = state.state

  if not vim.api.nvim_buf_is_valid(blackboard_state.blackboard_buf) then
    blackboard_state.blackboard_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[blackboard_state.blackboard_buf].bufhidden = 'hide'
    vim.bo[blackboard_state.blackboard_buf].buftype = 'nofile'
    vim.bo[blackboard_state.blackboard_buf].buflisted = false
    vim.bo[blackboard_state.blackboard_buf].swapfile = false
    if blackboard_state.original_buf and vim.api.nvim_buf_is_valid(blackboard_state.original_buf) then
      vim.bo[blackboard_state.blackboard_buf].filetype = vim.bo[blackboard_state.original_buf].filetype
    end
  end

  local parsed_marks_info = render.parse_marks_info(marks_info)

  vim.api.nvim_buf_set_lines(blackboard_state.blackboard_buf, 0, -1, false, parsed_marks_info.blackboardLines)
  render.add_highlights(parsed_marks_info)

  local width = render.desired_width(parsed_marks_info)
  local height = render.desired_height(parsed_marks_info)
  local col = math.max(vim.o.columns - width, 0)

  local cfg = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = 1,
    style = 'minimal',
    border = 'none',
    focusable = false,
  }

  if vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
    vim.api.nvim_win_set_config(blackboard_state.blackboard_win, cfg)
  else
    blackboard_state.blackboard_win = vim.api.nvim_open_win(blackboard_state.blackboard_buf, false, cfg)
    vim.wo[blackboard_state.blackboard_win].number = false
    vim.wo[blackboard_state.blackboard_win].relativenumber = false
    vim.wo[blackboard_state.blackboard_win].wrap = false
    vim.wo[blackboard_state.blackboard_win].winblend = 15
  end
end

function M.rerender_if_open()
  if vim.api.nvim_win_is_valid(state.state.blackboard_win) then
    M.render_blackboard()
  end
end

function M.toggle_mark_window()
  local blackboard_state = state.state
  blackboard_state.original_win = vim.api.nvim_get_current_win()
  blackboard_state.original_buf = vim.api.nvim_get_current_buf()

  if vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
    vim.api.nvim_win_hide(blackboard_state.blackboard_win)
    vim.api.nvim_buf_delete(blackboard_state.blackboard_buf, { force = true })
    blackboard_state.filepath_to_content_lines = {}
    return
  end

  M.render_blackboard()
  vim.api.nvim_set_current_win(blackboard_state.original_win)
end

return M
