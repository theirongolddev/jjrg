# jjrg

Search [jj (Jujutsu)](https://github.com/martinvonz/jj) diffs with [ripgrep](https://github.com/BurntSushi/ripgrep) in Neovim.

## Features

- Search through `jj diff` output using ripgrep patterns
- Live search with [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or [snacks.nvim](https://github.com/folke/snacks.nvim)
- Preview diff context for each match
- Jump to files from search results
- Quickfix fallback when no picker is available

## Requirements

- Neovim >= 0.9.0
- [jj](https://github.com/martinvonz/jj) installed and in PATH
- [ripgrep](https://github.com/BurntSushi/ripgrep) installed and in PATH

Optional:
- telescope.nvim for fuzzy picker
- snacks.nvim for fuzzy picker

## Installation

### lazy.nvim

```lua
{
  "username/jjrg",
  dependencies = {
    "nvim-telescope/telescope.nvim", -- optional
    -- or
    "folke/snacks.nvim", -- optional
  },
  config = function()
    require("jjrg").setup()
  end,
  keys = {
    { "<leader>jj", "<cmd>Jjrg<cr>", desc = "Search jj diff" },
    { "<leader>jd", "<cmd>JjrgDiff<cr>", desc = "Show jj diff" },
  },
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:Jjrg` | Open live search picker |
| `:JjrgSearch <pattern>` | Search for pattern in jj diff |
| `:JjrgDiff` | Show full jj diff in a buffer |
| `:JjrgTelescope` | Force Telescope picker |
| `:JjrgSnacks` | Force Snacks picker |

### Lua API

```lua
local jjrg = require("jjrg")

-- Live search picker
jjrg.live()

-- Search for a pattern
jjrg.search("pattern")

-- Show diff in buffer
jjrg.show_diff()
```

## Configuration

```lua
require("jjrg").setup({
  -- Additional ripgrep arguments
  rg_args = { "--color=never", "--no-heading", "--with-filename", "--line-number" },

  -- Additional jj diff arguments
  jj_args = {},

  -- Use telescope picker if available
  use_telescope = true,

  -- Use snacks.nvim picker if available (takes priority)
  use_snacks = true,

  -- Auto-open quickfix after search (fallback)
  quickfix_open = true,
})
```

## Running Tests

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## License

MIT
