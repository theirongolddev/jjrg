-- jjrg/telescope.lua
-- Telescope picker for jj diff search results
-- NOTE: Requires telescope.nvim to be installed
-- WARNING: Large diffs may cause performance issues

local M = {}

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  return M
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local core = require("jjrg.core")

---Create a telescope picker for jjrg results
---@param matches JjrgMatch[]
---@param opts? table Telescope picker options
function M.show_results(matches, opts)
  opts = opts or {}

  if #matches == 0 then
    vim.notify("No matches found", vim.log.levels.INFO)
    return
  end

  pickers
    .new(opts, {
      prompt_title = "JJ Diff Search",
      finder = finders.new_table({
        results = matches,
        entry_maker = function(entry)
          return {
            value = entry,
            display = string.format("%s: %s", entry.filename, entry.text),
            ordinal = entry.filename .. " " .. entry.text,
            filename = entry.filename,
            lnum = entry.lnum,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Diff Context",
        define_preview = function(self, entry, _)
          local lines = vim.split(entry.value.diff_context, "\n")
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = "diff"
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.filename and selection.filename ~= "unknown" then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
          end
        end)
        return true
      end,
    })
    :find()
end

---Live search jj diff with telescope
---@param opts? table
function M.live_search(opts)
  opts = opts or {}

  local diff_content, err = core.get_jj_diff()
  if err or not diff_content or diff_content == "" then
    vim.notify("Failed to get jj diff: " .. (err or "empty diff"), vim.log.levels.ERROR)
    return
  end

  pickers
    .new(opts, {
      prompt_title = "Search JJ Diff (live)",
      finder = finders.new_dynamic({
        fn = function(prompt)
          if not prompt or prompt == "" then
            return {}
          end
          local matches, _ = core.search_diff(prompt, diff_content)
          return matches
        end,
        entry_maker = function(entry)
          return {
            value = entry,
            display = string.format("%s: %s", entry.filename, entry.text),
            ordinal = entry.filename .. " " .. entry.text,
            filename = entry.filename,
            lnum = entry.lnum,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Diff Context",
        define_preview = function(self, entry, _)
          if entry and entry.value then
            local lines = vim.split(entry.value.diff_context, "\n")
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.bo[self.state.bufnr].filetype = "diff"
          end
        end,
      }),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.filename and selection.filename ~= "unknown" then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
          end
        end)
        return true
      end,
    })
    :find()
end

-- Register telescope extension
if has_telescope then
  return telescope.register_extension({
    exports = {
      jjrg = M.live_search,
      results = M.show_results,
    },
  })
end

return M
