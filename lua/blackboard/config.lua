local M = {}

---@type blackboard.Options
M.options = {
  not_under_func_symbol = '🔥',
  under_func_symbol = '╰─',
  mark_provider = nil,
}

---@param opts? blackboard.Options
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.options, opts or {})
end

return M
