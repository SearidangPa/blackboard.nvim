local M = {}

---@type blackboard.Options
M.options = {
  show_signs = true,
}

---@param opts? blackboard.Options
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.options, opts or {})
end

return M
