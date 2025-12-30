-- jjrg/config.lua
-- Configuration for jjrg plugin

local M = {}

---@class JjrgConfig
---@field rg_args string[] Additional ripgrep arguments
---@field jj_args string[] Additional jj diff arguments
---@field use_telescope boolean Use telescope picker if available
---@field use_snacks boolean Use snacks.nvim picker if available (takes priority)
---@field quickfix_open boolean Auto-open quickfix after search

---@type JjrgConfig
M.defaults = {
  rg_args = { "--color=never", "--no-heading", "--with-filename", "--line-number" },
  jj_args = {},
  use_telescope = true,
  use_snacks = true,
  quickfix_open = true,
  -- New options for future features
  max_results = 100,
  context_lines = 3,
  -- TODO: implement these options
  highlight_matches = true,
  auto_preview = true,
  highlight_duration = 1500, -- ms to show highlight
}

---@type JjrgConfig
M.options = vim.deepcopy(M.defaults)

---Setup configuration
---@param opts? JjrgConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
