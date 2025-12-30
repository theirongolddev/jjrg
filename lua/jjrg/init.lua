-- jjrg - Search jj diff with ripgrep
-- A Neovim plugin for quickly searching through jj (Jujutsu) diffs
-- Author: theirongolddev
-- License: MIT

local M = {}

local config = require("jjrg.config")
local core = require("jjrg.core")

---Setup the plugin
---@param opts? JjrgConfig
function M.setup(opts)
  config.setup(opts)
end

---Search jj diff with a pattern
---@param pattern string The search pattern
---@param opts? {jj_args?: string[], use_telescope?: boolean, use_snacks?: boolean}
function M.search(pattern, opts)
  opts = opts or {}

  local matches, err = core.search(pattern, opts.jj_args)
  if err then
    vim.notify("jjrg: " .. err, vim.log.levels.ERROR)
    return
  end

  if #matches == 0 then
    vim.notify("jjrg: No matches found", vim.log.levels.INFO)
    return
  end

  -- Try snacks first if preferred
  local use_snacks = opts.use_snacks
  if use_snacks == nil then
    use_snacks = config.options.use_snacks
  end

  if use_snacks then
    local has_snacks, snacks_picker = pcall(require, "jjrg.snacks")
    if has_snacks and snacks_picker.show_results then
      snacks_picker.show_results(matches)
      return
    end
  end

  -- Try telescope if preferred
  local use_telescope = opts.use_telescope
  if use_telescope == nil then
    use_telescope = config.options.use_telescope
  end

  if use_telescope then
    local has_telescope, telescope_picker = pcall(require, "jjrg.telescope")
    if has_telescope and telescope_picker.show_results then
      telescope_picker.show_results(matches)
      return
    end
  end

  -- Fallback to quickfix
  local qf_items = core.to_quickfix(matches)
  vim.fn.setqflist(qf_items, "r")
  vim.fn.setqflist({}, "a", { title = "jjrg: " .. pattern })
  if config.options.quickfix_open then
    vim.cmd("copen")
  end
end

---Open live search picker
---@param opts? {use_telescope?: boolean, use_snacks?: boolean}
function M.live(opts)
  opts = opts or {}

  -- Try snacks first
  local use_snacks = opts.use_snacks
  if use_snacks == nil then
    use_snacks = config.options.use_snacks
  end

  if use_snacks then
    local has_snacks, snacks_picker = pcall(require, "jjrg.snacks")
    if has_snacks and snacks_picker.live_search then
      snacks_picker.live_search()
      return
    end
  end

  -- Try telescope
  local use_telescope = opts.use_telescope
  if use_telescope == nil then
    use_telescope = config.options.use_telescope
  end

  if use_telescope then
    local has_telescope, telescope_picker = pcall(require, "jjrg.telescope")
    if has_telescope and telescope_picker.live_search then
      telescope_picker.live_search()
      return
    end
  end

  -- Fallback: prompt for pattern
  vim.ui.input({ prompt = "Search jj diff: " }, function(input)
    if input and input ~= "" then
      M.search(input, opts)
    end
  end)
end

---Show the full jj diff in a buffer
function M.show_diff()
  local diff, err = core.get_jj_diff()
  if err then
    vim.notify("jjrg: " .. err, vim.log.levels.ERROR)
    return
  end
  if not diff or diff == "" then
    vim.notify("jjrg: No diff output", vim.log.levels.INFO)
    return
  end

  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(diff, "\n"))
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  -- Open in a split
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, "jj-diff")
end

-- Export core for advanced usage
M.core = core
M.config = config

return M
