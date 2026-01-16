local M = {}

---@type blackboard.State
M.state = {
  blackboard_win = -1,
  blackboard_buf = -1,
  current_mark = '',
  original_win = -1,
  original_buf = -1,
  filepath_to_content_lines = {},
  mark_to_line = {},
  sign_autocmd_group = nil,
}

return M
