local M = {}

---@class blackboard.ProjectMarkRecord
---@field filepath string Project-relative path
---@field fallback_line number 1-based
---@field col number 0-based
---@field func_start_row? number 0-based, from TS range
---@field func_end_row? number 0-based, from TS range (exclusive)
---@field ratio? number 0..1, relative within function

---@class blackboard.ProjectMarksDb
---@field version number
---@field project_root string
---@field marks table<string, blackboard.ProjectMarkRecord>

---@param mark string
---@return boolean
local function is_valid_mark(mark)
  return type(mark) == 'string' and #mark == 1 and mark:match '^[a-z]$' ~= nil
end

---@param root string
---@return string
local function project_id(root)
  ---@diagnostic disable-next-line: undefined-field
  return vim.fn.sha256(root)
end

---@param root string
---@return string
local function db_path_for_root(root)
  local dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'blackboard', 'project_marks')
  vim.fn.mkdir(dir, 'p')
  return vim.fs.joinpath(dir, project_id(root) .. '.json')
end

---@return string?
local function get_project_root()
  local bufname = vim.api.nvim_buf_get_name(0)
  local start = bufname ~= '' and vim.fs.dirname(bufname) or vim.fn.getcwd()

  local matches = vim.fs.find('.git', {
    path = start,
    upward = true,
  })

  local git_dir = matches and matches[1] or nil
  if not git_dir then
    return nil
  end

  return vim.fs.dirname(git_dir)
end

---@param root string
---@return blackboard.ProjectMarksDb
local function load_db(root)
  local path = db_path_for_root(root)

  ---@diagnostic disable-next-line: undefined-field
  if vim.uv.fs_stat(path) then
    local ok_read, lines = pcall(vim.fn.readfile, path)
    if ok_read and lines and #lines > 0 then
      local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
      if ok_decode and decoded and type(decoded) == 'table' and type(decoded.marks) == 'table' then
        decoded.version = decoded.version or 1
        decoded.project_root = decoded.project_root or root
        return decoded
      end
    end
  end

  return {
    version = 1,
    project_root = root,
    marks = {},
  }
end

---@param root string
---@param db blackboard.ProjectMarksDb
local function save_db(root, db)
  local path = db_path_for_root(root)
  db.version = db.version or 1
  db.project_root = db.project_root or root
  db.marks = db.marks or {}

  local encoded = vim.json.encode(db)
  vim.fn.writefile({ encoded }, path)
end

-- DB cache: mtime-based invalidation to avoid repeated disk reads
---@type table<string, { db: blackboard.ProjectMarksDb, mtime: number }>
local db_cache = {}

---@param root string
---@return blackboard.ProjectMarksDb
local function load_db_cached(root)
  local path = db_path_for_root(root)
  ---@diagnostic disable-next-line: undefined-field
  local stat = vim.uv.fs_stat(path)
  local mtime = stat and stat.mtime.sec or 0

  local cached = db_cache[root]
  if cached and cached.mtime == mtime then
    return cached.db
  end

  local db = load_db(root)
  db_cache[root] = { db = db, mtime = mtime }
  return db
end

---@param root string
local function invalidate_cache(root)
  db_cache[root] = nil
end

---@param root string
---@param abs_path string
---@return string?
local function to_project_relpath(root, abs_path)
  root = vim.fs.normalize(root)
  abs_path = vim.fs.normalize(abs_path)

  local prefix = root .. '/'
  if abs_path:sub(1, #prefix) ~= prefix then
    return nil
  end

  return abs_path:sub(#prefix + 1)
end

---@param root string
---@param relpath string
---@return string
local function to_abs_path(root, relpath)
  return vim.fs.normalize(vim.fs.joinpath(root, relpath))
end

---@param bufnr number
local function ensure_filetype(bufnr)
  if vim.bo[bufnr].filetype ~= '' then
    return
  end

  local ok_filetype, plenary_filetype = pcall(require, 'plenary.filetype')
  if not ok_filetype then
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local ft = plenary_filetype.detect(name, {})
  if ft and ft ~= '' then
    vim.bo[bufnr].filetype = ft
  end
end

---@param abs_path string
---@return number?
local function load_buf(abs_path)
  ---@diagnostic disable-next-line: undefined-field
  if not vim.uv.fs_stat(abs_path) then
    return nil
  end

  local bufnr = vim.fn.bufadd(abs_path)
  vim.fn.bufload(bufnr)
  ensure_filetype(bufnr)
  return bufnr
end

---@param bufnr number
---@param row1 number
---@return string
local function get_line_text(bufnr, row1)
  local line = vim.api.nvim_buf_get_lines(bufnr, row1 - 1, row1, false)[1] or ''
  return vim.trim(line)
end

---@param filepath string
---@param line number
---@return string?
local function get_cached_line_text(filepath, line)
  local bb_state = require 'blackboard.state'
  local cache = bb_state.state.filepath_to_content_lines

  if not cache[filepath] then
    ---@diagnostic disable-next-line: undefined-field
    local stat = vim.uv.fs_stat(filepath)
    if not stat then
      return nil
    end
    local ok, lines = pcall(vim.fn.readfile, filepath)
    if ok and lines then
      cache[filepath] = lines
    end
  end

  local lines = cache[filepath]
  return lines and lines[line] and vim.trim(lines[line]) or nil
end

---@param row0 number
---@param start_row number
---@param end_row number
---@return number
local function ratio_in_range(row0, start_row, end_row)
  local span = end_row - start_row
  if span <= 0 then
    return 0
  end

  local clamped = math.min(math.max(row0, start_row), end_row - 1)
  local ratio = (clamped - start_row) / span
  return math.min(math.max(ratio, 0), 1)
end

---@param bufnr number
---@param mark blackboard.ProjectMarkRecord
---@return number row1
---@return number col0
---@return string func_name
local function resolve_mark_position(bufnr, mark)
  local row1 = mark.fallback_line
  local col0 = mark.col
  local func_name = ''

  if mark.ratio and mark.func_start_row then
    local util_ts = require 'blackboard.bookmarks.analysis'
    local ctx = util_ts.find_function_by_position(bufnr, mark.func_start_row)
    if ctx and ctx.start_row and ctx.end_row then
      local span = ctx.end_row - ctx.start_row
      local row0 = ctx.start_row + math.floor((mark.ratio * span) + 0.5)
      row0 = math.min(math.max(row0, ctx.start_row), ctx.end_row - 1)
      row1 = row0 + 1
      func_name = ctx.func_name or ''
    end
  end

  return row1, col0, func_name
end

---@param mark string
M.set_mark = function(mark)
  if not is_valid_mark(mark) then
    vim.notify('BlackboardMark expects a single letter a-z', vim.log.levels.ERROR)
    return
  end

  local root = get_project_root()
  if not root then
    vim.notify('BlackboardMark: not inside a git project (no .git found)', vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local abs_path = vim.api.nvim_buf_get_name(bufnr)
  if abs_path == '' then
    vim.notify('BlackboardMark: current buffer has no file path', vim.log.levels.ERROR)
    return
  end

  local relpath = to_project_relpath(root, abs_path)
  if not relpath then
    vim.notify('BlackboardMark: file is outside git project', vim.log.levels.ERROR)
    return
  end

  local row1, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  local line_text = get_line_text(bufnr, row1)

  local util_ts = require 'blackboard.bookmarks.analysis'
  local func_ctx = util_ts.enclosing_function_context(bufnr, row1 - 1, col0)

  -- TODO: do not store func_start_row, func_end_row
  -- dynamically compute them on display
  -- save the ratio of the position within the function instead,
  -- so that it can be resolved even if the function moves
  local record = {
    filepath = relpath,
    fallback_line = row1,
    col = col0,
    func_start_row = func_ctx and func_ctx.start_row or nil,
    func_end_row = func_ctx and func_ctx.end_row or nil,
    ratio = func_ctx and ratio_in_range(row1 - 1, func_ctx.start_row, func_ctx.end_row) or nil,
  }

  local db = load_db_cached(root)
  db.marks[mark] = record
  save_db(root, db)
  invalidate_cache(root)

  if line_text ~= '' then
    vim.notify(string.format('Blackboard: set %s (%s:%d)', mark, relpath, row1))
  else
    vim.notify(string.format('Blackboard: set %s (%s:%d)', mark, relpath, row1))
  end
end

M.clear_marks = function()
  local root = get_project_root()
  if not root then
    vim.notify('BlackboardClear: not inside a git project (no .git found)', vim.log.levels.ERROR)
    return
  end

  local db = load_db_cached(root)
  if not db.marks or next(db.marks) == nil then
    return
  end

  db.marks = {}
  save_db(root, db)
  invalidate_cache(root)
end

---@param mark string
M.delete_mark = function(mark)
  if not is_valid_mark(mark) then
    vim.notify('DelMark expects a single letter a-z', vim.log.levels.ERROR)
    return
  end

  local root = get_project_root()
  if not root then
    vim.notify('DelMark: not inside a git project (no .git found)', vim.log.levels.ERROR)
    return
  end

  local db = load_db_cached(root)
  local record = db.marks[mark]
  if not record then
    vim.notify('DelMark: no mark set for ' .. mark, vim.log.levels.WARN)
    return
  end

  local relpath = record.filepath
  local line = record.fallback_line
  db.marks[mark] = nil
  save_db(root, db)
  invalidate_cache(root)

  vim.notify(string.format('Blackboard: deleted mark %s (%s:%d)', mark, relpath, line))
end

---@return blackboard.MarkInfo[]
M.list_marks = function()
  local root = get_project_root()
  if not root then
    return {}
  end

  local db = load_db_cached(root)
  local marks = {}

  for mark, record in pairs(db.marks) do
    local abs_path = to_abs_path(root, record.filepath)
    local bufnr = load_buf(abs_path)

    local row1 = record.fallback_line
    local col0 = record.col
    local func_name = ''
    local text

    if bufnr then
      row1, col0, func_name = resolve_mark_position(bufnr, record)
      text = get_line_text(bufnr, row1)
    else
      text = '<file missing>'
    end

    marks[#marks + 1] = {
      mark = mark,
      bufnr = bufnr or -1,
      filename = record.filepath,
      filepath = abs_path,
      filetype = bufnr and vim.bo[bufnr].filetype or '',
      line = row1,
      col = col0,
      ratio = record.ratio,
      nearest_func = func_name,
      text = string.format('%s:%d %s', record.filepath, row1, text),
      line_text = text,
    }
  end

  table.sort(marks, function(a, b)
    if a.mark ~= b.mark then
      return a.mark < b.mark
    end
    if a.filepath ~= b.filepath then
      return a.filepath < b.filepath
    end
    return a.line < b.line
  end)

  return marks
end

--- Lightweight version of list_marks that doesn't force-load buffers
--- Use this for rendering when we don't need full buffer context
---@return blackboard.MarkInfo[]
M.list_marks_lightweight = function()
  local root = get_project_root()
  if not root then
    return {}
  end

  local db = load_db_cached(root)
  local marks = {}

  for mark, record in pairs(db.marks) do
    local abs_path = to_abs_path(root, record.filepath)
    -- Only use buffer if already loaded
    local bufnr = vim.fn.bufnr(abs_path)
    local is_loaded = bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)

    local row1 = record.fallback_line
    local col0 = record.col
    local func_name = ''
    local text = ''
    local filetype = ''

    if is_loaded then
      row1, col0, func_name = resolve_mark_position(bufnr, record)
      text = get_line_text(bufnr, row1)
      filetype = vim.bo[bufnr].filetype
    else
      text = get_cached_line_text(abs_path, row1) or '<not loaded>'
      filetype = vim.filetype.match { filename = abs_path } or ''
    end

    marks[#marks + 1] = {
      mark = mark,
      bufnr = bufnr > 0 and bufnr or -1,
      filename = record.filepath,
      filepath = abs_path,
      filetype = filetype,
      line = row1,
      col = col0,
      ratio = record.ratio,
      nearest_func = func_name,
      text = string.format('%s:%d %s', record.filepath, row1, text),
      line_text = text,
    }
  end

  table.sort(marks, function(a, b)
    if a.mark ~= b.mark then
      return a.mark < b.mark
    end
    if a.filepath ~= b.filepath then
      return a.filepath < b.filepath
    end
    return a.line < b.line
  end)

  return marks
end

---@param mark string
M.jump_to_mark = function(mark)
  if not is_valid_mark(mark) then
    vim.notify('BlackboardJump expects a single letter a-z', vim.log.levels.ERROR)
    return
  end

  local root = get_project_root()
  if not root then
    vim.notify('BlackboardJump: not inside a git project (no .git found)', vim.log.levels.ERROR)
    return
  end

  local db = load_db_cached(root)
  local record = db.marks[mark]
  if not record then
    vim.notify('BlackboardJump: no mark set for ' .. mark, vim.log.levels.ERROR)
    return
  end

  local abs_path = to_abs_path(root, record.filepath)
  ---@diagnostic disable-next-line: undefined-field
  if not vim.uv.fs_stat(abs_path) then
    vim.notify('BlackboardJump: file missing: ' .. record.filepath, vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(abs_path))
  local bufnr = vim.api.nvim_get_current_buf()
  ensure_filetype(bufnr)

  local row1, col0 = record.fallback_line, record.col
  if record.func_start_row then
    row1, col0 = resolve_mark_position(bufnr, record)
  end

  vim.api.nvim_win_set_cursor(0, { row1, col0 })
  vim.cmd 'normal! zz'
end

return M
