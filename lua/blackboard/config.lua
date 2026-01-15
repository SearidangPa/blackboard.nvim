local M = {}

---@type blackboard.Options
M.options = {
  mark_provider = nil,
  override_vim_m_key = false,
}

---@param opts? blackboard.Options
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.options, opts or {})
end

return M
