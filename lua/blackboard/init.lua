local config = require 'blackboard.config'
local window = require 'blackboard.ui.window'
local actions = require 'blackboard.bookmarks.actions'
local project_provider = require 'blackboard.bookmarks.providers.project'

local M = {}

-- Timer for debouncing BufWritePost re-renders
local render_timer = nil

---@param preview_width? number
---@return table
local function picker_layout(preview_width)
	return {
		layout = {
			box = 'horizontal',
			width = vim.o.columns,
			min_width = 120,
			height = 0,
			{
				box = 'vertical',
				border = 'rounded',
				title = '{title} {live} {flags}',
				{ win = 'input', height = 1,     border = 'bottom' },
				{ win = 'list',  border = 'none' },
			},
			{
				win = 'preview',
				title = '{preview}',
				border = 'rounded',
				width = preview_width or 0.65,
			},
		},
	}
end

---@param func_name string
---@return string
local function short_function_name(func_name)
	return func_name:match '[%.:]([^%.:]+)$' or func_name
end

--- Setup the plugin
---@param opts blackboard.Options
M.setup = function(opts)
	config.setup(opts)
	-- Setup sign column marks
	if config.options.show_signs then
		local signs = require 'blackboard.ui.signs'
		signs.setup_autocmds()
	end

	-- Auto-refresh blackboard window on file save (updates function names after LSP rename, etc.)
	-- Debounced to prevent rapid re-renders on frequent saves
	vim.api.nvim_create_user_command('DelMark', function(cmd_opts)
		local mark = vim.trim(cmd_opts.args or '')
		if mark == '' then
			M.clear_marks()
			return
		end

		M.delete_mark(mark)
	end, { nargs = '?' })

	local blackboard_group = vim.api.nvim_create_augroup('blackboard', { clear = true })
	vim.api.nvim_create_autocmd('BufWritePost', {
		group = blackboard_group,
		callback = function()
			if render_timer then
				render_timer:stop()
			end
			render_timer = vim.defer_fn(function()
				window.rerender_if_open()
				render_timer = nil
			end, 100)
		end,
	})
end

M.toggle_mark_window = window.toggle_mark_window
M.mark = actions.mark
M.clear_marks = actions.clear_marks
M.delete_mark = actions.delete_mark
M.jump = actions.jump

--- Prompt user for a character (a-z) to set a mark
M.prompt_mark = function()
	local char = vim.fn.getcharstr()
	if char:match '^[a-z]$' then
		M.mark(char)
	end
end

--- Pick marks with snacks picker
---@param opts? { preview_width?: number }
M.pick = function(opts)
	opts = opts or {}
	local marks = project_provider.list_marks()

	if #marks == 0 then
		vim.notify('Blackboard: no marks set', vim.log.levels.INFO)
		return
	end

	local analysis = require 'blackboard.bookmarks.analysis'
	local items = {}
	for _, mark in ipairs(marks) do
		local nearest_func = mark.nearest_func or ''
		if nearest_func == '' and mark.bufnr > 0 and vim.api.nvim_buf_is_valid(mark.bufnr) then
			local func_ctx = analysis.enclosing_function_context(mark.bufnr, mark.line - 1, mark.col)
			if func_ctx and func_ctx.func_name ~= '' then
				nearest_func = func_ctx.func_name
			end
		end

		local func_name = nearest_func ~= '' and short_function_name(nearest_func) or ''

		local text
		local display_text = {}
		display_text[#display_text + 1] = { mark.mark .. ": ", "BlackboardSign" }
		if func_name ~= '' then
			display_text[#display_text + 1] = { func_name, "Function" }
			text = func_name
		else
			local filename = mark.filename ~= '' and mark.filename or mark.filepath
			local basename = vim.fn.fnamemodify(filename, ':t')
			display_text[#display_text + 1] = { basename .. ':' .. mark.line, "Comment" }
			text = basename
		end


		items[#items + 1] = {
			mark = mark.mark,
			text = text,
			display = display_text,
			file = mark.filepath,
			pos = { mark.line, mark.col },
			preview_title = string.format('%s:%d', mark.filename, mark.line),
		}
	end

	Snacks.picker {
		title = 'Blackboard Marks',
		items = items,
		format = function(item)
			return item.display
		end,
		layout = picker_layout(opts.preview_width),
		confirm = function(picker, item)
			picker:close()
			if not item or not item.mark then
				return
			end
			project_provider.jump_to_mark(item.mark)
			window.render_blackboard()
		end,
	}
end


return M
