---@meta

---@class blackboard.State
---@field blackboard_win number
---@field blackboard_buf number
---@field current_mark string
---@field original_win number
---@field original_buf number
---@field filepath_to_content_lines table<string, string[]>
---@field mark_to_line table<string, number>
---@field sign_autocmd_group? number

---@class blackboard.Options
---@field override_vim_m_key? boolean
---@field show_signs? boolean

---@class blackboard.MarkInfo
---@field mark string
---@field bufnr number
---@field filename string
---@field filepath string
---@field filetype string
---@field line number
---@field col number
---@field nearest_func string
---@field text string
---@field line_text string
