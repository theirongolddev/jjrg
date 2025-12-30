-- jjrg/config.lua
-- Configuration for jjrg plugin

local M = {}

---@class JjrgConfig
---@field rg_args string[] Additional ripgrep arguments
---@field jj_args string[] Additional jj diff arguments
---@field use_telescope boolean Use telescope picker if available
---@field use_snacks boolean Use snacks.nvim picker if available (takes priority)
---@field quickfix_open boolean Auto-open quickfix after search
---@field max_results number Maximum number of results to show
---@field context_lines number Number of context lines around matches
---@field highlight_matches boolean Highlight matched text in file
---@field auto_preview boolean Auto-show preview in picker
---@field highlight_duration number Duration in ms to show highlight
---@field command_timeout number Timeout in ms for external commands
---@field debug boolean Enable debug logging

---@type JjrgConfig
M.defaults = {
	rg_args = { "--color=never", "--no-heading", "--with-filename", "--line-number" },
	jj_args = {},
	use_telescope = true,
	use_snacks = true,
	quickfix_open = true,
	max_results = 100,
	context_lines = 3,
	highlight_matches = true,
	auto_preview = true,
	highlight_duration = 1500, -- ms to show highlight
	command_timeout = 10000, -- ms timeout for external commands
	debug = true, -- enable debug logging (set to false when done testing)
}

---@type JjrgConfig
M.options = vim.deepcopy(M.defaults)

---Setup configuration
---@param opts? JjrgConfig
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
