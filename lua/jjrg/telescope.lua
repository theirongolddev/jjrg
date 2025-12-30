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
local config = require("jjrg.config")

-- Highlight namespace for search matches
local hl_ns = vim.api.nvim_create_namespace("jjrg_telescope_highlight")

---Highlight matched text temporarily using extmarks
---@param bufnr number
---@param lnum number 1-indexed line number
---@param col_start number 0-indexed start column
---@param col_end number 0-indexed end column
---@param duration? number Duration in ms
local function highlight_match(bufnr, lnum, col_start, col_end, duration)
  duration = duration or config.options.highlight_duration or 1500
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
  vim.api.nvim_buf_set_extmark(bufnr, hl_ns, lnum - 1, col_start, {
    end_row = lnum - 1,
    end_col = col_end,
    hl_group = "Search",
  })
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
    end
  end, duration)
end

---Find match position in a line (case-insensitive)
---@param line_content string
---@param pattern string
---@return number|nil col_start
---@return number|nil col_end
local function find_match_position(line_content, pattern)
  if not pattern or pattern == "" then
    return nil, nil
  end
  local lower_line = line_content:lower()
  local lower_pattern = pattern:lower()
  local start_pos, end_pos = lower_line:find(lower_pattern, 1, true)
  if start_pos then
    return start_pos - 1, end_pos
  end
  return nil, nil
end

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
            display = string.format("%s:%d %s", entry.filename, entry.file_lnum or 0, entry.text),
            ordinal = entry.filename .. " " .. entry.text,
            filename = entry.filename,
            lnum = entry.lnum,
            file_lnum = entry.file_lnum,
            match_text = entry.text,
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
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          -- Capture values before closing
          local selection = action_state.get_selected_entry()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local search_text = picker and picker:_get_prompt() or ""

          actions.close(prompt_bufnr)

          if selection and selection.filename and selection.filename ~= "unknown" then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
            if selection.file_lnum then
              vim.schedule(function()
                local bufnr = vim.api.nvim_get_current_buf()
                local buf_name = vim.api.nvim_buf_get_name(bufnr)
                if not buf_name:match(vim.pesc(selection.filename) .. "$") then
                  return
                end
                local line_count = vim.api.nvim_buf_line_count(bufnr)
                if selection.file_lnum > line_count then
                  return
                end
                local file_lines = vim.api.nvim_buf_get_lines(bufnr, selection.file_lnum - 1, selection.file_lnum, false)
                local file_line = file_lines[1] or ""
                local pattern = (search_text ~= "" and search_text) or selection.match_text
                local col_start, col_end = find_match_position(file_line, pattern)
                if not col_start then
                  col_start = 0
                  col_end = 0
                end
                vim.api.nvim_win_set_cursor(0, { selection.file_lnum, col_start })
                vim.cmd("normal! zz")
                if col_end > col_start then
                  highlight_match(bufnr, selection.file_lnum, col_start, col_end)
                end
              end)
            end
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
            display = string.format("%s:%d %s", entry.filename, entry.file_lnum or 0, entry.text),
            ordinal = entry.filename .. " " .. entry.text,
            filename = entry.filename,
            lnum = entry.lnum,
            file_lnum = entry.file_lnum,
            match_text = entry.text,
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
          local selection = action_state.get_selected_entry()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local search_text = picker and picker:_get_prompt() or ""

          actions.close(prompt_bufnr)

          if selection and selection.filename and selection.filename ~= "unknown" then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
            if selection.file_lnum then
              vim.schedule(function()
                local bufnr = vim.api.nvim_get_current_buf()
                local buf_name = vim.api.nvim_buf_get_name(bufnr)
                if not buf_name:match(vim.pesc(selection.filename) .. "$") then
                  return
                end
                local line_count = vim.api.nvim_buf_line_count(bufnr)
                if selection.file_lnum > line_count then
                  return
                end
                local file_lines = vim.api.nvim_buf_get_lines(bufnr, selection.file_lnum - 1, selection.file_lnum, false)
                local file_line = file_lines[1] or ""
                local pattern = (search_text ~= "" and search_text) or selection.match_text
                local col_start, col_end = find_match_position(file_line, pattern)
                if not col_start then
                  col_start = 0
                  col_end = 0
                end
                vim.api.nvim_win_set_cursor(0, { selection.file_lnum, col_start })
                vim.cmd("normal! zz")
                if col_end > col_start then
                  highlight_match(bufnr, selection.file_lnum, col_start, col_end)
                end
              end)
            end
          end
        end)
        return true
      end,
    })
    :find()
end

-- Register telescope extension (side effect, don't return this)
if has_telescope then
  telescope.register_extension({
    exports = {
      jjrg = M.live_search,
      results = M.show_results,
    },
  })
end

return M
