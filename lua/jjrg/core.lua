-- jjrg/core.lua
-- Core functionality for searching jj diff with ripgrep
-- TODO: Add support for searching specific revisions
-- TODO: Add caching for repeated searches
-- FIXME: Handle binary files better
-- FIXME: Improve error messages for missing dependencies

local M = {}
local VERSION = "0.1.0"
local config = require("jjrg.config")

---@class JjrgMatch
---@field filename string The file path
---@field lnum number Line number in the diff
---@field col number Column number
---@field text string The matching line text
---@field diff_context string Context showing +/- lines

---Run a command and return stdout
---@param cmd string[]
---@return string? stdout
---@return string? error
local function run_cmd(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil, result.stderr or "Command failed"
  end
  return result.stdout, nil
end

---Get jj diff output
---@param args? string[] Additional arguments for jj diff
---@return string? diff_output
---@return string? error
function M.get_jj_diff(args)
  local cmd = { "jj", "diff" }
  vim.list_extend(cmd, config.options.jj_args)
  if args then
    vim.list_extend(cmd, args)
  end
  return run_cmd(cmd)
end

---Search diff content with ripgrep
---@param pattern string The search pattern
---@param diff_content string The diff content to search
---@return JjrgMatch[] matches
---@return string? error
function M.search_diff(pattern, diff_content)
  if not pattern or pattern == "" then
    return {}, "Empty search pattern"
  end

  if not diff_content or diff_content == "" then
    return {}, "No diff content to search"
  end

  -- Write diff to temp file for ripgrep
  local tmpfile = vim.fn.tempname()
  local f = io.open(tmpfile, "w")
  if not f then
    return {}, "Failed to create temp file"
  end
  f:write(diff_content)
  f:close()

  -- Build ripgrep command
  local cmd = { "rg" }
  vim.list_extend(cmd, config.options.rg_args)
  table.insert(cmd, pattern)
  table.insert(cmd, tmpfile)

  local output, err = run_cmd(cmd)
  os.remove(tmpfile)

  if err then
    -- rg returns exit 1 for no matches, which is fine
    if output == nil or output == "" then
      return {}, nil
    end
  end

  if not output or output == "" then
    return {}, nil
  end

  -- Parse ripgrep output
  local matches = {}
  local lines = vim.split(diff_content, "\n")
  local current_file = nil

  -- Build file map from diff headers (jj format: "Modified regular file path/to/file:")
  local file_map = {} -- line_num -> filename
  for i, line in ipairs(lines) do
    local file_match = line:match("^Modified regular file (.+):$")
      or line:match("^Added regular file (.+):$")
      or line:match("^Removed regular file (.+):$")
    if file_match then
      current_file = file_match
    end
    if current_file then
      file_map[i] = current_file
    end
  end

  -- Parse rg output (format: filename:lnum:text)
  for line in output:gmatch("[^\n]+") do
    local _, lnum_str, text = line:match("^([^:]+):(%d+):(.*)$")
    if lnum_str then
      local lnum = tonumber(lnum_str)
      -- Find which file this line belongs to
      local filename = nil
      for i = lnum, 1, -1 do
        if file_map[i] then
          filename = file_map[i]
          break
        end
      end

      table.insert(matches, {
        filename = filename or "unknown",
        lnum = lnum,
        col = 1,
        text = text,
        diff_context = M.get_context(lines, lnum, 2),
      })
    end
  end

  return matches, nil
end

---Get context lines around a match
---@param lines string[]
---@param lnum number
---@param context number
---@return string
function M.get_context(lines, lnum, context)
  local start_line = math.max(1, lnum - context)
  local end_line = math.min(#lines, lnum + context)
  local ctx_lines = {}
  for i = start_line, end_line do
    local prefix = i == lnum and ">" or " "
    table.insert(ctx_lines, prefix .. lines[i])
  end
  return table.concat(ctx_lines, "\n")
end

---Convert matches to quickfix list format
---@param matches JjrgMatch[]
---@return table[] qf_items
function M.to_quickfix(matches)
  local items = {}
  for _, match in ipairs(matches) do
    table.insert(items, {
      filename = match.filename,
      lnum = match.lnum,
      col = match.col,
      text = match.text,
    })
  end
  return items
end

---Main search function
---@param pattern string
---@param jj_args? string[]
---@return JjrgMatch[] matches
---@return string? error
function M.search(pattern, jj_args)
  local diff, err = M.get_jj_diff(jj_args)
  if err then
    return {}, err
  end
  if not diff or diff == "" then
    return {}, "No diff output from jj"
  end
  return M.search_diff(pattern, diff)
end

return M
