local render = require 'blackboard.ui.render'
local project_provider = require 'blackboard.bookmarks.providers.project'
local actions = require 'blackboard.bookmarks.actions'

local M = {}

local manager_buf = -1
local manager_win = -1
---@type table<number, string[]>
local line_marks = {}
---@type table<number, string>
local line_text = {}
local rendering = false
local project_buf = -1

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
  local marks_info = project_provider.list_marks_lightweight(project_buf > 0 and project_buf or origin_buf)
  local parsed = render.parse_marks_info(marks_info)

  if origin_buf and vim.api.nvim_buf_is_valid(origin_buf) then
    vim.bo[manager_buf].filetype = vim.bo[origin_buf].filetype
  end

  rendering = true
  vim.bo[manager_buf].modifiable = true
  vim.api.nvim_buf_set_lines(manager_buf, 0, -1, false, parsed.blackboardLines)
  render.add_highlights(parsed, manager_buf)
  rendering = false

  line_marks = parsed.lineMarks or {}
  line_text = parsed.blackboardLines or {}
  return parsed
end

local sync_deleted_lines

local function close()
  sync_deleted_lines(false)

  if vim.api.nvim_win_is_valid(manager_win) then
    vim.api.nvim_win_close(manager_win, true)
  end
  if vim.api.nvim_buf_is_valid(manager_buf) then
    vim.api.nvim_buf_delete(manager_buf, { force = true })
  end
  manager_win = -1
  manager_buf = -1
  project_buf = -1
  line_marks = {}
  line_text = {}
  rendering = false
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

---@param should_refresh? boolean
sync_deleted_lines = function(should_refresh)
  if rendering or not vim.api.nvim_buf_is_valid(manager_buf) then
    return
  end

  local remaining = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(manager_buf, 0, -1, false)) do
    remaining[line] = (remaining[line] or 0) + 1
  end

  local deleted_marks = {}
  for row, marks in pairs(line_marks) do
    if #marks > 0 then
      local text = line_text[row] or ''
      if (remaining[text] or 0) > 0 then
        remaining[text] = remaining[text] - 1
      else
        for _, mark in ipairs(marks) do
          deleted_marks[mark] = true
        end
      end
    end
  end

  if next(deleted_marks) then
    for mark in pairs(deleted_marks) do
      actions.delete_mark(mark)
    end

    -- Prevent repeated syncs (for example :wq triggers BufWriteCmd, then close/BufWipeout)
    -- from trying to delete the same marks again and showing spurious warnings.
    for row, marks in pairs(line_marks) do
      local kept = {}
      for _, mark in ipairs(marks) do
        if not deleted_marks[mark] then
          kept[#kept + 1] = mark
        end
      end
      line_marks[row] = kept
    end
  end

  vim.bo[manager_buf].modified = false

  if should_refresh then
    refresh()
  end
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
  project_buf = origin_buf

  manager_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(manager_buf, 'blackboard://marks')
  vim.bo[manager_buf].bufhidden = 'wipe'
  vim.bo[manager_buf].buftype = 'acwrite'
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
  vim.keymap.set('n', 'D', clear_all, map_opts)
  vim.keymap.set('n', '<CR>', jump_to_current_line_mark, map_opts)
  vim.keymap.set('n', 'q', close, map_opts)
  vim.keymap.set('n', '<Esc>', close, map_opts)

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = manager_buf,
    callback = function()
      sync_deleted_lines(true)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    buffer = manager_buf,
    once = true,
    callback = function()
      sync_deleted_lines(false)
    end,
  })
end

return M
