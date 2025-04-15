local M = {}

---@type blackboard.State
local blackboard_state = {
  blackboard_win = -1,
  blackboard_buf = -1,
  popup_win = -1,
  popup_buf = -1,
  current_mark = '',
  original_win = -1,
  original_buf = -1,
  filepath_to_content_lines = {},
  mark_to_line = {},
  show_nearest_func = false,
}

---@type blackboard.Options
local options = {
  show_nearest_func = false,
  not_under_func_symbol = '🔥',
  under_func_symbol = '╰─',
}

--- Setup the plugin
---@param opts blackboard.Options
M.setup = function(opts)
  options = vim.tbl_deep_extend('force', options, opts or {})
  blackboard_state.show_nearest_func = options.show_nearest_func
end

local function load_all_file_contents(show_nearest_func)
  local util_mark_info = require 'util_blackboard_mark_info'
  local all_accessible_marks = util_mark_info.get_accessible_marks_info(show_nearest_func)
  local grouped_marks_by_filepath = util_mark_info.group_marks_info_by_filepath(all_accessible_marks)
  local pp = require 'plenary.path'
  for filepath, _ in pairs(grouped_marks_by_filepath) do
    local data = pp:new(filepath):read()
    local content_lines = vim.split(data, '\n', { plain = true })
    blackboard_state.filepath_to_content_lines[filepath] = content_lines
  end
end

---@class blackboard.ParsedMarks
---@field blackboardLines string[]
---@field virtualLines table<number, blackboard.VirtualLine>

---@class blackboard.VirtualLine
---@field filename string
---@field func_name string

---@param marks_info blackboard.MarkInfo[]
---@return blackboard.ParsedMarks
local function parse_grouped_marks_info(marks_info)
  local util_mark_info = require 'util_blackboard_mark_info'
  local grouped_marks_by_filename = util_mark_info.group_marks_info_by_filepath(marks_info)
  local blackboardLines = {}
  local virtualLines = {}

  for filepath, grouped_marks_info in pairs(grouped_marks_by_filename) do
    local filename = vim.fn.fnamemodify(filepath, ':t')
    table.sort(grouped_marks_info, function(a, b)
      return a.line < b.line
    end)

    if #blackboardLines == 0 then
      table.insert(blackboardLines, filename)
    end

    for _, mark_info in ipairs(grouped_marks_info) do
      local currentLine = #blackboardLines + 1
      virtualLines[currentLine] = {
        filename = filename,
        func_name = mark_info.nearest_func,
      }
      if mark_info.nearest_func then
        table.insert(blackboardLines, string.format('%s %s: %s', options.under_func_symbol, mark_info.mark, mark_info.text))
      else
        table.insert(blackboardLines, string.format('%s %s: %s', options.not_under_func_symbol, mark_info.mark, mark_info.text))
      end
      blackboard_state.mark_to_line[mark_info.mark] = currentLine
    end
  end

  return {
    blackboardLines = blackboardLines,
    virtualLines = virtualLines,
  }
end

local function set_cursor_for_popup_win(target_line, mark_char)
  local line_count = vim.api.nvim_buf_line_count(blackboard_state.popup_buf)
  if target_line >= line_count then
    target_line = line_count
  end
  vim.api.nvim_win_set_cursor(blackboard_state.popup_win, { target_line, 2 }) -- Move cursor after the arrow

  vim.fn.sign_define('MySign', { text = mark_char, texthl = 'DiagnosticInfo' })
  vim.fn.sign_place(0, 'MySignGroup', 'MySign', blackboard_state.popup_buf, { lnum = target_line, priority = 100 })
end

---@param marks_info blackboard.MarkInfo[]
local function show_fullscreen_popup_at_mark(marks_info)
  local util_mark_info = require 'util_blackboard_mark_info'
  local mark_char = util_mark_info.get_mark_char(blackboard_state)
  if not mark_char then
    return
  elseif blackboard_state.current_mark == mark_char and vim.api.nvim_win_is_valid(blackboard_state.popup_win) then
    return
  end
  blackboard_state.current_mark = mark_char

  local mark_info = util_mark_info.retrieve_mark_info(marks_info, mark_char)
  local target_line = mark_info.line

  local file_content_lines = blackboard_state.filepath_to_content_lines[mark_info.filepath]
  assert(file_content_lines, string.format('File content not found for %s', mark_info.filepath))

  if not vim.api.nvim_win_is_valid(blackboard_state.popup_win) then
    blackboard_state.popup_buf = vim.api.nvim_create_buf(false, true)
    local util_blackboard_preview = require 'util_blackboard_preview'
    util_blackboard_preview.open_popup_win(blackboard_state, mark_info)
  end
  file_content_lines = blackboard_state.filepath_to_content_lines[mark_info.filepath]
  vim.api.nvim_buf_set_lines(blackboard_state.popup_buf, 0, -1, false, file_content_lines)
  set_cursor_for_popup_win(target_line, mark_char)
end

---@param marks_info blackboard.MarkInfo[]
local function attach_autocmd_blackboard_buf(marks_info)
  local augroup = vim.api.nvim_create_augroup('blackboard_group', { clear = true })
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = blackboard_state.blackboard_buf,
    group = augroup,
    callback = function()
      show_fullscreen_popup_at_mark(marks_info)
      vim.api.nvim_set_current_win(blackboard_state.blackboard_win)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    buffer = blackboard_state.blackboard_buf,
    group = augroup,
    callback = function()
      if vim.api.nvim_win_is_valid(blackboard_state.popup_win) then
        vim.api.nvim_win_close(blackboard_state.popup_win, true)
      end
    end,
  })

  vim.api.nvim_create_autocmd('BufWinLeave', {
    buffer = blackboard_state.blackboard_buf,
    group = augroup,
    callback = function()
      if vim.api.nvim_get_current_win() == blackboard_state.blackboard_win then
        vim.api.nvim_win_set_buf(blackboard_state.original_win, blackboard_state.original_buf)
        vim.defer_fn(function()
          if not vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
            return
          end
          vim.api.nvim_set_current_win(blackboard_state.original_win)
          vim.api.nvim_win_set_buf(blackboard_state.blackboard_win, blackboard_state.blackboard_buf)
        end, 0)
      end
    end,
  })
  local bb = require 'blackboard'
  vim.keymap.set('n', '<CR>', function()
    bb.jump_to_mark()
  end, { noremap = true, silent = true, buffer = blackboard_state.blackboard_buf })
end

local function add_highlights(parsedMarks)
  local blackboardLines = parsedMarks.blackboardLines
  vim.api.nvim_set_hl(0, 'FileHighlight', { fg = '#5097A4' })
  ---@diagnostic disable-next-line: deprecated
  vim.api.nvim_buf_add_highlight(blackboard_state.blackboard_buf, -1, 'FileHighlight', 0, 0, -1)

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

local function make_func_line(data)
  if not data.func_name or data.func_name == '' then
    return ''
  end
  return '❯ ' .. data.func_name
end

local function get_virtual_lines_no_func_lines(filename, last_seen_filename)
  if filename == last_seen_filename then
    return nil
  end
  return { { { '', '' } }, { { filename, 'FileHighlight' } } }
end

local function get_virtual_lines(filename, funcLine, last_seen_filename, last_seen_func, show_nearest_func)
  if not show_nearest_func or funcLine == '' then
    return get_virtual_lines_no_func_lines(filename, last_seen_filename)
  end
  if filename ~= last_seen_filename then
    return { { { '', '' } }, { { filename, 'FileHighlight' } }, { { funcLine, '@function' } } }
  end
  if funcLine ~= last_seen_func then
    return { { { '', '' } }, { { funcLine, '@function' } } }
  end
  return nil
end

local function add_virtual_lines(parsedMarks)
  local ns_blackboard = vim.api.nvim_create_namespace 'blackboard_extmarks'
  local last_seen_filename = ''
  local last_seen_func = ''

  for lineNum, data in pairs(parsedMarks.virtualLines) do
    local filename = data.filename or ''
    local funcLine = make_func_line(data)
    local extmarkLine = lineNum - 1

    local virt_lines
    if extmarkLine == 1 then
      vim.api.nvim_buf_set_extmark(blackboard_state.blackboard_buf, ns_blackboard, 0, 0, {
        virt_lines = { { { filename, 'FileHighlight' } } },
        virt_lines_above = true,
        hl_mode = 'combine',
        priority = 10,
      })
      if blackboard_state.show_nearest_func and funcLine ~= '' then
        virt_lines = { { { funcLine, '@function' } } }
      end
    elseif extmarkLine > 1 then
      virt_lines = get_virtual_lines(filename, funcLine, last_seen_filename, last_seen_func, blackboard_state.show_nearest_func)
    end

    if virt_lines then
      vim.api.nvim_buf_set_extmark(blackboard_state.blackboard_buf, ns_blackboard, extmarkLine, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        hl_mode = 'combine',
        priority = 10,
      })
    end
    last_seen_filename = filename
    last_seen_func = funcLine
  end
end

---@param marks_info blackboard.MarkInfo[]
local function create_new_blackboard(marks_info)
  vim.cmd 'vsplit'
  blackboard_state.blackboard_win = vim.api.nvim_get_current_win()
  local plenary_filetype = require 'plenary.filetype'
  local filetype = plenary_filetype.detect(vim.api.nvim_buf_get_name(0), {})

  if not vim.api.nvim_buf_is_valid(blackboard_state.blackboard_buf) then
    blackboard_state.blackboard_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[blackboard_state.blackboard_buf].bufhidden = 'hide'
    vim.bo[blackboard_state.blackboard_buf].buftype = 'nofile'
    vim.bo[blackboard_state.blackboard_buf].buflisted = false
    vim.bo[blackboard_state.blackboard_buf].swapfile = false
    vim.bo[blackboard_state.blackboard_buf].filetype = filetype
  end

  local map_opts = { buffer = blackboard_state.blackboard_buf, noremap = true, silent = true }
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
      vim.api.nvim_win_close(blackboard_state.blackboard_win, true)
      blackboard_state.blackboard_win = -1
    end
  end, map_opts)

  local util_mark_info = require 'util_blackboard_mark_info'

  local local_marks_info = marks_info or util_mark_info.get_accessible_marks_info(blackboard_state.show_nearest_func)
  local parsed_marks_info = parse_grouped_marks_info(local_marks_info)
  vim.api.nvim_buf_set_lines(blackboard_state.blackboard_buf, 0, -1, false, parsed_marks_info.blackboardLines)
  add_highlights(parsed_marks_info)
  add_virtual_lines(parsed_marks_info)

  vim.api.nvim_win_set_width(blackboard_state.blackboard_win, math.floor(vim.o.columns / 4))
  vim.wo[blackboard_state.blackboard_win].number = false
  vim.wo[blackboard_state.blackboard_win].relativenumber = false
  vim.wo[blackboard_state.blackboard_win].wrap = false
  vim.api.nvim_win_set_buf(blackboard_state.blackboard_win, blackboard_state.blackboard_buf)
end

--- === Exported functions ===

M.toggle_mark_window = function()
  blackboard_state.original_win = vim.api.nvim_get_current_win()
  blackboard_state.original_buf = vim.api.nvim_get_current_buf()

  if vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
    vim.api.nvim_win_hide(blackboard_state.blackboard_win)
    vim.api.nvim_buf_delete(blackboard_state.blackboard_buf, { force = true })
    vim.api.nvim_del_augroup_by_name 'blackboard_group'
    blackboard_state.filepath_to_content_lines = {}
    return
  end

  local util_mark_info = require 'util_blackboard_mark_info'
  local marks_info = util_mark_info.get_accessible_marks_info(blackboard_state.show_nearest_func)
  create_new_blackboard(marks_info)
  vim.api.nvim_set_current_win(blackboard_state.original_win)
  load_all_file_contents(blackboard_state.show_nearest_func)
  attach_autocmd_blackboard_buf(marks_info)
end

M.toggle_mark_context = function()
  if not vim.api.nvim_win_is_valid(blackboard_state.blackboard_win) then
    return
  else
    vim.api.nvim_win_hide(blackboard_state.blackboard_win)
    vim.api.nvim_buf_delete(blackboard_state.blackboard_buf, { force = true })
    vim.api.nvim_del_augroup_by_name 'blackboard_group'
  end
  blackboard_state.show_nearest_func = not blackboard_state.show_nearest_func

  local util_mark_info = require 'util_blackboard_mark_info'
  local marks_info = util_mark_info.get_accessible_marks_info(blackboard_state.show_nearest_func)
  create_new_blackboard(marks_info)
  vim.api.nvim_set_current_win(blackboard_state.original_win)
  attach_autocmd_blackboard_buf(marks_info)
end

vim.api.nvim_create_user_command('BlackboardToggle', M.toggle_mark_window, {
  desc = 'Toggle Blackboard',
})

vim.api.nvim_create_user_command('BlackboardToggleContext', M.toggle_mark_context, {
  desc = 'Toggle Mark Context',
})

return M
