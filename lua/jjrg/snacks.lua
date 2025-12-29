-- jjrg/snacks.lua
-- Snacks.nvim picker integration for jj diff search

local M = {}

local has_snacks, Snacks = pcall(require, "snacks")
if not has_snacks then
  return M
end

local core = require("jjrg.core")

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
    -- Track current file from diff headers
    local file_match = line:match("^%+%+%+ b/(.+)$")
    if file_match then
      current_file = file_match
    end

    -- Include lines that have actual content (skip empty and diff metadata)
    if current_file and line ~= "" and not line:match("^diff ") and not line:match("^index ") and not line:match("^%-%-%-") and not line:match("^%+%+%+") and not line:match("^@@") then
      max_filename_len = math.max(max_filename_len, #current_file)
      table.insert(items, {
        idx = #items + 1,
        score = #items + 1,
        text = current_file .. " " .. line, -- searchable
        filename = current_file,
        match_text = line,
        lnum = i,
        diff_context = core.get_context(lines, i, 3),
      })
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
      picker:close()
      if item and item.filename and item.filename ~= "unknown" then
        vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
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
