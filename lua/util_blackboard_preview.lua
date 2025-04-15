local util_blackboard_preview = {}

---@param blackboard_state blackboard.State
---@param mark_info blackboard.MarkInfo
function util_blackboard_preview.open_popup_win(blackboard_state, mark_info)
  local filetype = mark_info.filetype
  local lang = vim.treesitter.language.get_lang(filetype)
  if not pcall(vim.treesitter.start, blackboard_state.popup_buf, lang) then
    vim.bo[blackboard_state.popup_buf].syntax = filetype
  end

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local width = math.floor(editor_width * 3 / 4)
  local height = editor_height - 3
  local row = 1
  local col = 0

  blackboard_state.popup_win = vim.api.nvim_open_win(blackboard_state.popup_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'none',
  })

  vim.bo[blackboard_state.popup_buf].buftype = 'nofile'
  vim.bo[blackboard_state.popup_buf].bufhidden = 'wipe'
  vim.bo[blackboard_state.popup_buf].swapfile = false
  vim.bo[blackboard_state.popup_buf].filetype = mark_info.filetype
  vim.wo[blackboard_state.popup_win].wrap = false
  vim.wo[blackboard_state.popup_win].number = true
  vim.wo[blackboard_state.popup_win].relativenumber = true
  vim.api.nvim_set_option_value('winhl', 'Normal:Normal', { win = blackboard_state.popup_win }) -- Match background
end

return util_blackboard_preview
