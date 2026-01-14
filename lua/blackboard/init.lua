local M = {}

---@type blackboard.State
local blackboard_state = {
  blackboard_win = -1,
  blackboard_buf = -1,
  current_mark = '',
  original_win = -1,
  original_buf = -1,
  filepath_to_content_lines = {},
  mark_to_line = {},
}

---@type blackboard.Options
local options = {
  not_under_func_symbol = '🔥',
  under_func_symbol = '╰─',
  mark_provider = nil,
}

---@return blackboard.MarkProvider
local function get_provider()
  if options.mark_provider then
    return options.mark_provider
  end

  return require 'blackboard.mark_provider_project'
end

---@param msg string
local function notify_err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

--- Setup the plugin
---@param opts blackboard.Options
M.setup = function(opts)
  options = vim.tbl_deep_extend('force', options, opts or {})

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

---@class blackboard.ParsedMarks
---@field blackboardLines string[]
---@field virtualLines string[]

---@param marks_info blackboard.MarkInfo[]
---@return blackboard.ParsedMarks
local function parse_marks_info(marks_info)
  local blackboardLines = {}
  local virtualLines = {}

  if not marks_info or #marks_info == 0 then
    return {
      blackboardLines = { 'No marks set' },
      virtualLines = { '' },
    }
  end

  for _, mark_info in ipairs(marks_info) do
    local currentLine = #blackboardLines + 1
    local nearest_func = mark_info.nearest_func or ''

    virtualLines[currentLine] = nearest_func

    local symbol = options.not_under_func_symbol
    if nearest_func ~= '' then
      symbol = options.under_func_symbol
    end

    table.insert(blackboardLines, string.format('%s %s: %s', symbol, mark_info.mark, mark_info.text))
    blackboard_state.mark_to_line[mark_info.mark] = currentLine
  end

  return {
    blackboardLines = blackboardLines,
    virtualLines = virtualLines,
  }
end

---@param parsedMarks blackboard.ParsedMarks
local function add_highlights(parsedMarks)
  local blackboardLines = parsedMarks.blackboardLines
  vim.api.nvim_set_hl(0, 'MarkHighlight', { fg = '#f1c232' })

  for lineIdx, line in ipairs(blackboardLines) do
    local markMatch = line:match '([A-Za-z]):'
    if markMatch then
      local endCol = line:find(markMatch .. ':')
      if endCol then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(blackboard_state.blackboard_buf, -1, 'MarkHighlight', lineIdx - 1, endCol - 1, endCol)
      end
    end
  end
end

---@param parsedMarks blackboard.ParsedMarks
local function add_virtual_lines(parsedMarks)
  local ns_blackboard = vim.api.nvim_create_namespace 'blackboard_extmarks'
  vim.api.nvim_buf_clear_namespace(blackboard_state.blackboard_buf, ns_blackboard, 0, -1)

  local last_seen_func = nil

  for line_num, func_name in ipairs(parsedMarks.virtualLines) do
    local extmark_line = line_num - 1
    local func_line = func_name ~= '' and ('❯ ' .. func_name) or ''

    if func_line ~= last_seen_func then
      vim.api.nvim_buf_set_extmark(blackboard_state.blackboard_buf, ns_blackboard, extmark_line, 0, {
        virt_lines = { { { func_line, '@function' } } },
        virt_lines_above = true,
        hl_mode = 'combine',
        priority = 10,
      })
    end

    last_seen_func = func_line
  end
end

---@param parsed_marks_info blackboard.ParsedMarks
---@return number
local function desired_height(parsed_marks_info)
  local height = #parsed_marks_info.blackboardLines
  if height == 0 then
    height = 1
  end

  local max_height = math.floor(vim.o.lines * 0.8)
  if height > max_height then
    height = max_height
  end

  return height
end

local function render_blackboard()
  local provider = get_provider()
  local marks_info = provider.list_marks()

  if not vim.api.nvim_buf_is_valid(blackboard_state.blackboard_buf) then
    blackboard_state.blackboard_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[blackboard_state.blackboard_buf].bufhidden = 'hide'
    vim.bo[blackboard_state.blackboard_buf].buftype = 'nofile'
    vim.bo[blackboard_state.blackboard_buf].buflisted = false
    vim.bo[blackboard_state.blackboard_buf].swapfile = false
    vim.bo[blackboard_state.blackboard_buf].filetype = vim.bo[blackboard_state.original_buf].filetype
  end

  local parsed_marks_info = parse_marks_info(marks_info)

  vim.api.nvim_buf_set_lines(blackboard_state.blackboard_buf, 0, -1, false, parsed_marks_info.blackboardLines)
  add_highlights(parsed_marks_info)
  add_virtual_lines(parsed_marks_info)

  local width = math.floor(vim.o.columns / 3)
  local height = desired_height(parsed_marks_info)

  local cfg = {
    relative = 'editor',
    width = width,
    height = height,
    col = vim.o.columns - width - 1,
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

local function rerender_if_open()
  if vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
    render_blackboard()
  end
end

--- === Exported functions ===

M.toggle_mark_window = function()
  blackboard_state.original_win = vim.api.nvim_get_current_win()
  blackboard_state.original_buf = vim.api.nvim_get_current_buf()

  if vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
    vim.api.nvim_win_hide(blackboard_state.blackboard_win)
    vim.api.nvim_buf_delete(blackboard_state.blackboard_buf, { force = true })
    blackboard_state.filepath_to_content_lines = {}
    return
  end

  render_blackboard()
  vim.api.nvim_set_current_win(blackboard_state.original_win)
end

---@param mark string
M.mark = function(mark)
  local provider = get_provider()
  provider.set_mark(mark)
  rerender_if_open()
end

---@param mark string
M.unmark = function(mark)
  local provider = get_provider()
  provider.unset_mark(mark)
  rerender_if_open()
end

---@param mark string
M.jump = function(mark)
  local provider = get_provider()
  provider.jump_to_mark(mark)
  rerender_if_open()
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

vim.api.nvim_create_user_command('BlackboardJump', function(cmd)
  M.jump(cmd.args)
end, {
  desc = 'Jump to project mark (a-z)',
  nargs = 1,
})

vim.keymap.set('n', '<Leader>bb', M.toggle_mark_window, { desc = 'Toggle Blackboard' })

return M
