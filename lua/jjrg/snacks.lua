-- jjrg/snacks.lua
-- Snacks.nvim picker integration for jj diff search

local M = {}

local has_snacks, snacks = pcall(require, "snacks")
if not has_snacks then
  return M
end

local core = require("jjrg.core")

---Format a match for display in snacks picker
---@param match JjrgMatch
---@return table
local function format_item(match)
  return {
    text = string.format("%s: %s", match.filename, match.text),
    file = match.filename ~= "unknown" and match.filename or nil,
    data = match,
  }
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

  local items = vim.tbl_map(format_item, matches)

  snacks.picker.pick({
    title = "JJ Diff Search",
    items = items,
    format = function(item)
      return {
        { item.data.filename, "Directory" },
        { ": " },
        { item.data.text },
      }
    end,
    preview = function(ctx)
      local lines = vim.split(ctx.item.data.diff_context, "\n")
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
      vim.bo[ctx.buf].filetype = "diff"
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      end
    end,
  })
end

---Live search jj diff with snacks picker
---@param opts? table
function M.live_search(opts)
  opts = opts or {}

  local diff_content, err = core.get_jj_diff()
  if err or not diff_content or diff_content == "" then
    vim.notify("Failed to get jj diff: " .. (err or "empty diff"), vim.log.levels.ERROR)
    return
  end

  snacks.picker.pick({
    title = "Search JJ Diff",
    live = true,
    source = function(query)
      if not query or query == "" then
        return {}
      end
      local matches, _ = core.search_diff(query, diff_content)
      return vim.tbl_map(format_item, matches)
    end,
    format = function(item)
      return {
        { item.data.filename, "Directory" },
        { ": " },
        { item.data.text },
      }
    end,
    preview = function(ctx)
      if ctx.item and ctx.item.data then
        local lines = vim.split(ctx.item.data.diff_context, "\n")
        vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
        vim.bo[ctx.buf].filetype = "diff"
      end
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
      end
    end,
  })
end

---Search with prompt using snacks input
---@param opts? table
function M.search(opts)
  opts = opts or {}

  snacks.input({
    prompt = "Search jj diff: ",
  }, function(input)
    if not input or input == "" then
      return
    end
    local matches, err = core.search(input)
    if err then
      vim.notify("Search failed: " .. err, vim.log.levels.ERROR)
      return
    end
    M.show_results(matches, opts)
  end)
end

return M
