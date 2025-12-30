-- jjrg/snacks.lua
-- Snacks.nvim picker integration for jj diff search

local M = {}

local has_snacks, Snacks = pcall(require, "snacks")
if not has_snacks then
  return M
end

local core = require("jjrg.core")

-- Highlight namespace for search matches
local hl_ns = vim.api.nvim_create_namespace("jjrg_highlight")

---Parse line number from jj diff line format
---jj format: "   9    9: content" where second number is new line number
---@param line string
---@return number|nil file_lnum The line number in the actual file
---@return string content The line content without line numbers
local function parse_diff_line(line)
  -- Match pattern: optional old_num, spaces, new_num, colon, content
  -- Examples: "   9    9: content" or "       10: content" (added line)
  local new_lnum, content = line:match("^%s*%d*%s+(%d+):%s?(.*)$")
  if new_lnum then
    return tonumber(new_lnum), content
  end
  -- Removed lines have format: "  9     : content" - no new line number
  local removed_content = line:match("^%s*%d+%s+:%s?(.*)$")
  if removed_content then
    return nil, removed_content
  end
  return nil, line
end

---Highlight matched text temporarily
---@param bufnr number
---@param lnum number 1-indexed line number
---@param col_start number 0-indexed start column
---@param col_end number 0-indexed end column (-1 for end of line)
---@param duration? number Duration in ms (default 1500)
local function highlight_match(bufnr, lnum, col_start, col_end, duration)
  duration = duration or 1500
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, hl_ns, "Search", lnum - 1, col_start, col_end)
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
    end
  end, duration)
end

---Find match position in a line (case-insensitive)
---@param line_content string The line content to search in
---@param pattern string The search pattern
---@return number|nil col_start 0-indexed start column
---@return number|nil col_end 0-indexed end column
local function find_match_position(line_content, pattern)
  if not pattern or pattern == "" then
    return nil, nil
  end
  -- Try case-insensitive plain text match first
  local lower_line = line_content:lower()
  local lower_pattern = pattern:lower()
  local start_pos, end_pos = lower_line:find(lower_pattern, 1, true)
  if start_pos then
    return start_pos - 1, end_pos -- convert to 0-indexed
  end
  return nil, nil
end

---Show search results in snacks picker
---@param matches JjrgMatch[]
---@param opts? table
function M.show_results(matches, opts)
  opts = opts or {}

  if #matches == 0 then
    vim.notify("No matches found", vim.log.levels.INFO)
    return
  end

  -- Build items with required fields
  local items = {}
  local max_filename_len = 0

  for i, match in ipairs(matches) do
    max_filename_len = math.max(max_filename_len, #match.filename)
    table.insert(items, {
      idx = i,
      score = i,
      text = match.filename .. " " .. match.text, -- searchable text
      filename = match.filename,
      match_text = match.text,
      diff_context = match.diff_context,
    })
  end

  max_filename_len = max_filename_len + 2

  Snacks.picker({
    title = "JJ Diff Search",
    items = items,
    format = function(item)
      local ret = {}
      ret[#ret + 1] = { ("%-" .. max_filename_len .. "s"):format(item.filename), "SnacksPickerLabel" }
      ret[#ret + 1] = { item.match_text, "SnacksPickerComment" }
      return ret
    end,
    preview = function(ctx)
      if ctx.item and ctx.item.diff_context then
        local lines = vim.split(ctx.item.diff_context, "\n")
        vim.api.nvim_buf_set_lines(ctx.preview.buf, 0, -1, false, lines)
        vim.bo[ctx.preview.buf].filetype = "diff"
      end
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.filename and item.filename ~= "unknown" then
        vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
      end
    end,
  })
end

---Live search jj diff with snacks picker
---Loads all diff lines and lets snacks fuzzy filter them
---@param opts? table
function M.live_search(opts)
  opts = opts or {}

  local diff_content, err = core.get_jj_diff()
  if err or not diff_content or diff_content == "" then
    vim.notify("Failed to get jj diff: " .. (err or "empty diff"), vim.log.levels.ERROR)
    return
  end

  -- Parse diff into searchable items
  local lines = vim.split(diff_content, "\n")
  local items = {}
  local current_file = nil
  local max_filename_len = 0

  for i, line in ipairs(lines) do
    -- Track current file from diff headers (jj format: "Modified regular file path/to/file:")
    local file_match = line:match("^Modified regular file (.+):$")
      or line:match("^Added regular file (.+):$")
      or line:match("^Removed regular file (.+):$")
    if file_match then
      current_file = file_match
    end

    -- Include lines that have actual content (skip file headers and "..." markers)
    if current_file and line ~= "" and not line:match("^Modified ") and not line:match("^Added ") and not line:match("^Removed ") and not line:match("^%s*%.%.%.$") then
      local file_lnum, content = parse_diff_line(line)
      -- Only include lines that exist in the new file (have a line number)
      if file_lnum and content ~= "" then
        max_filename_len = math.max(max_filename_len, #current_file)
        table.insert(items, {
          idx = #items + 1,
          score = #items + 1,
          text = current_file .. " " .. content, -- searchable
          filename = current_file,
          match_text = content,
          file_lnum = file_lnum, -- actual line number in file
          diff_lnum = i,
          diff_context = core.get_context(lines, i, 3),
        })
      end
    end
  end

  if #items == 0 then
    vim.notify("No searchable content in diff", vim.log.levels.INFO)
    return
  end

  max_filename_len = max_filename_len + 2

  local search_pattern = ""

  Snacks.picker({
    title = "Search JJ Diff",
    items = items,
    format = function(item)
      local ret = {}
      ret[#ret + 1] = { ("%-" .. max_filename_len .. "s"):format(item.filename), "SnacksPickerLabel" }
      ret[#ret + 1] = { string.format(":%d ", item.file_lnum or 0), "SnacksPickerIdx" }
      ret[#ret + 1] = { item.match_text, "SnacksPickerComment" }
      return ret
    end,
    preview = function(ctx)
      if ctx.item and ctx.item.diff_context then
        local plines = vim.split(ctx.item.diff_context, "\n")
        vim.api.nvim_buf_set_lines(ctx.preview.buf, 0, -1, false, plines)
        vim.bo[ctx.preview.buf].filetype = "diff"
      end
    end,
    on_change = function(picker)
      -- Capture the current search pattern
      search_pattern = picker.input.filter.search or ""
    end,
    confirm = function(picker, item)
      -- Capture final search pattern before closing
      local final_pattern = picker.input.filter.search or search_pattern
      picker:close()
      if item and item.filename and item.filename ~= "unknown" then
        vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
        if item.file_lnum then
          local bufnr = vim.api.nvim_get_current_buf()
          -- Get the actual line content from the file
          local file_line = vim.api.nvim_buf_get_lines(bufnr, item.file_lnum - 1, item.file_lnum, false)[1] or ""
          -- Find where the match is in the line
          local col_start, col_end = find_match_position(file_line, final_pattern)
          -- Default to beginning of content if no match found
          col_start = col_start or 0
          col_end = col_end or (col_start + #final_pattern)
          -- Set cursor at start of match
          vim.api.nvim_win_set_cursor(0, { item.file_lnum, col_start })
          -- Center the line on screen
          vim.cmd("normal! zz")
          -- Highlight only the matched text
          highlight_match(bufnr, item.file_lnum, col_start, col_end)
        end
      end
    end,
  })
end

---Search with prompt then show results
---@param opts? table
function M.search(opts)
  opts = opts or {}

  Snacks.input({
    prompt = "Search jj diff: ",
  }, function(input)
    if not input or input == "" then
      return
    end
    local matches, search_err = core.search(input)
    if search_err then
      vim.notify("Search failed: " .. search_err, vim.log.levels.ERROR)
      return
    end
    M.show_results(matches, opts)
  end)
end

return M
