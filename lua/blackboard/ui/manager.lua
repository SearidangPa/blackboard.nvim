local render = require 'blackboard.ui.render'
local project_provider = require 'blackboard.bookmarks.providers.project'
local actions = require 'blackboard.bookmarks.actions'

local M = {}

local manager_buf = -1
local manager_win = -1
---@type table<number, string[]>
local line_marks = {}

local function clamp(value, min_value, max_value)
  return math.min(math.max(value, min_value), max_value)
end

local function centered_offset(total, size)
  return math.max(math.floor((total - size) / 2), 0)
end

local function compute_layout(parsed)
  local max_width = math.max(vim.o.columns - 4, 1)
  local max_height = math.max(vim.o.lines - 4, 1)

  local min_width = clamp(math.floor(vim.o.columns * 0.5), 60, max_width)
  local min_height = clamp(math.floor(vim.o.lines * 0.4), 15, max_height)

  local width = clamp(render.desired_width(parsed), min_width, max_width)
  local height = clamp(render.desired_height(parsed), min_height, max_height)

  return width, height, centered_offset(vim.o.lines, height), centered_offset(vim.o.columns, width)
end

local function render_into_buffer(origin_buf)
  local marks_info = project_provider.list_marks_lightweight()
  local parsed = render.parse_marks_info(marks_info)

  if origin_buf and vim.api.nvim_buf_is_valid(origin_buf) then
    vim.bo[manager_buf].filetype = vim.bo[origin_buf].filetype
  end

  vim.bo[manager_buf].modifiable = true
  vim.api.nvim_buf_set_lines(manager_buf, 0, -1, false, parsed.blackboardLines)
  vim.bo[manager_buf].modifiable = false
  render.add_highlights(parsed, manager_buf)

  line_marks = parsed.lineMarks or {}
  return parsed
end

local function close()
  if vim.api.nvim_win_is_valid(manager_win) then
    vim.api.nvim_win_close(manager_win, true)
  end
  if vim.api.nvim_buf_is_valid(manager_buf) then
    vim.api.nvim_buf_delete(manager_buf, { force = true })
  end
  manager_win = -1
  manager_buf = -1
  line_marks = {}
end

local function refresh()
  if not vim.api.nvim_win_is_valid(manager_win) or not vim.api.nvim_buf_is_valid(manager_buf) then
    return
  end
  local parsed = render_into_buffer(nil)
  local width, height, row, col = compute_layout(parsed)
  vim.api.nvim_win_set_config(manager_win, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
  })
end

local function delete_current_line_marks()
  if not vim.api.nvim_win_is_valid(manager_win) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(manager_win)[1]
  local marks = line_marks[row]
  if not marks or #marks == 0 then
    return
  end
  for _, mark in ipairs(marks) do
    actions.delete_mark(mark)
  end
  refresh()
end

local function clear_all()
  actions.clear_marks()
  refresh()
end

local function jump_to_current_line_mark()
  if not vim.api.nvim_win_is_valid(manager_win) then
    return
  end

  local row = vim.api.nvim_win_get_cursor(manager_win)[1]
  local marks = line_marks[row]
  if not marks or #marks == 0 then
    return
  end

  close()
  actions.jump(marks[1])
end

function M.open()
  if vim.api.nvim_win_is_valid(manager_win) then
    vim.api.nvim_set_current_win(manager_win)
    return
  end

  local origin_buf = vim.api.nvim_get_current_buf()

  manager_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[manager_buf].bufhidden = 'wipe'
  vim.bo[manager_buf].buftype = 'nofile'
  vim.bo[manager_buf].buflisted = false
  vim.bo[manager_buf].swapfile = false

  local parsed = render_into_buffer(origin_buf)
  local width, height, row, col = compute_layout(parsed)

  manager_win = vim.api.nvim_open_win(manager_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Blackboard ',
    title_pos = 'center',
    focusable = true,
  })
  vim.wo[manager_win].number = false
  vim.wo[manager_win].relativenumber = false
  vim.wo[manager_win].wrap = false
  vim.wo[manager_win].cursorline = true
  vim.wo[manager_win].winblend = 0

  local map_opts = { buffer = manager_buf, nowait = true, silent = true }
  vim.keymap.set('n', 'd', delete_current_line_marks, map_opts)
  vim.keymap.set('n', 'D', clear_all, map_opts)
  vim.keymap.set('n', '<CR>', jump_to_current_line_mark, map_opts)
  vim.keymap.set('n', 'q', close, map_opts)
  vim.keymap.set('n', '<Esc>', close, map_opts)

  vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, {
    buffer = manager_buf,
    once = true,
    callback = function()
      vim.schedule(close)
    end,
  })
end

return M
