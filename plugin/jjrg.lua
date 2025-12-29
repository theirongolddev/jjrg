-- plugin/jjrg.lua
-- Auto-loaded by Neovim to set up commands

if vim.g.loaded_jjrg then
  return
end
vim.g.loaded_jjrg = true

-- Create user commands
vim.api.nvim_create_user_command("JjrgSearch", function(args)
  require("jjrg").search(args.args)
end, {
  nargs = 1,
  desc = "Search jj diff with ripgrep",
})

vim.api.nvim_create_user_command("Jjrg", function()
  require("jjrg").live()
end, {
  nargs = 0,
  desc = "Open live jj diff search picker",
})

vim.api.nvim_create_user_command("JjrgDiff", function()
  require("jjrg").show_diff()
end, {
  nargs = 0,
  desc = "Show jj diff in a buffer",
})

vim.api.nvim_create_user_command("JjrgTelescope", function()
  require("jjrg").live({ use_telescope = true, use_snacks = false })
end, {
  nargs = 0,
  desc = "Open jj diff search with Telescope",
})

vim.api.nvim_create_user_command("JjrgSnacks", function()
  require("jjrg").live({ use_snacks = true, use_telescope = false })
end, {
  nargs = 0,
  desc = "Open jj diff search with Snacks",
})
