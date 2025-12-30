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

---Highlight matched text temporarily using extmarks (modern API)
---@param bufnr number
---@param lnum number 1-indexed line number
---@param col_start number 0-indexed start column
---@param col_end number 0-indexed end column
---@param duration? number Duration in ms (default 1500)
local function highlight_match(bufnr, lnum, col_start, col_end, duration)
  duration = duration or 1500
  -- Clear any existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)
  -- Use extmarks for highlighting (0-indexed line and columns)
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
      file_lnum = match.file_lnum,
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
      -- Capture values before closing picker
      local filter = picker.input and picker.input.filter
      local search_text = filter and (filter.search or filter.pattern) or ""
      local filename = item and item.filename
      local file_lnum = item and item.file_lnum
      local match_text = item and item.match_text

      picker:close()

      if filename and filename ~= "unknown" then
        vim.cmd("edit " .. vim.fn.fnameescape(filename))
        if file_lnum then
          vim.schedule(function()
            local bufnr = vim.api.nvim_get_current_buf()
            local buf_name = vim.api.nvim_buf_get_name(bufnr)
            if not buf_name:match(vim.pesc(filename) .. "$") then
              return
            end
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            if file_lnum > line_count then
              return
            end
            local file_lines = vim.api.nvim_buf_get_lines(bufnr, file_lnum - 1, file_lnum, false)
            local file_line = file_lines[1] or ""
            -- Try search text first, fallback to match_text
            local pattern = (search_text ~= "" and search_text) or match_text
            local col_start, col_end = find_match_position(file_line, pattern)
            if not col_start then
              col_start = 0
              col_end = 0
            end
            vim.api.nvim_win_set_cursor(0, { file_lnum, col_start })
            vim.cmd("normal! zz")
            if col_end > col_start then
              highlight_match(bufnr, file_lnum, col_start, col_end)
            end
          end)
        end
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
    confirm = function(picker, item)
      -- Capture all values BEFORE closing picker (avoid race condition)
      local filter = picker.input and picker.input.filter
      local search_text = filter and (filter.search or filter.pattern) or ""
      local filename = item and item.filename
      local file_lnum = item and item.file_lnum

      picker:close()

      if filename and filename ~= "unknown" then
        vim.cmd("edit " .. vim.fn.fnameescape(filename))
        if file_lnum then
          -- Schedule to ensure buffer is loaded, using captured values
          vim.schedule(function()
            local bufnr = vim.api.nvim_get_current_buf()
            -- Verify we're in the right buffer
            local buf_name = vim.api.nvim_buf_get_name(bufnr)
            if not buf_name:match(vim.pesc(filename) .. "$") then
              return
            end
            -- Get the actual line content from the file
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            if file_lnum > line_count then
              return
            end
            local file_lines = vim.api.nvim_buf_get_lines(bufnr, file_lnum - 1, file_lnum, false)
            local file_line = file_lines[1] or ""
            -- Find where the match is in the line
            local col_start, col_end = find_match_position(file_line, search_text)
            -- Default to beginning if no match found
            if not col_start then
              col_start = 0
              col_end = 0
            end
            -- Set cursor at start of match (row is 1-indexed, col is 0-indexed)
            vim.api.nvim_win_set_cursor(0, { file_lnum, col_start })
            -- Center the line on screen
            vim.cmd("normal! zz")
            -- Highlight only the matched text if we found it
            if col_end > col_start then
              highlight_match(bufnr, file_lnum, col_start, col_end)
            end
          end)
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
