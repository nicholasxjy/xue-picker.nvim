# xue-picker.nvim

A bottom-docked picker built on Neovim's `vim._core.ui2` command-line area. Supports smart file finding, asynchronous live grep, multi-selection quickfix export, toggleable previews, and `vim.ui` replacements.

## Features

- **Native Bottom-Docked UI**: Deeply integrated into Neovim 0.12+ `ui2` command-line area for a compact, seamless interface.
- **High-Performance Search**:
  - Optional multi-threaded fuzzy file and content search powered by [fff](https://github.com/dmtrKovalenko/fff)'s native library.
  - Built-in standalone matcher with ripgrep fallback for speed and reliability.
- **Rich Builtin Pickers**: Files (`files` / `smart`), live search (`live_grep` / `grep_word`), buffers (`buffers`), diagnostics (`diagnostics`), marks (`marks`), history (`history`), and more.
- **Full-Featured**: Multi-selection, split / tab actions, quickfix export, async previews, Lualine statusline extension, and drop-in replacements for `vim.ui.select` and `vim.ui.input`.

## Requirements

- **Neovim 0.12+** (with `vim._core.ui2` support)
- **[ripgrep (`rg`)](https://github.com/BurntSushi/ripgrep)**: Required for file scanning and grep fallback.
- *(Optional)* **[fff](https://github.com/dmtrKovalenko/fff)**: Required for `builtin.smart` and fff-accelerated content search (native binary required).
- *(Optional)* Icon provider: `mini.icons` or `nvim-web-devicons`.

Run `:checkhealth xue-picker` to inspect dependencies and environment status.

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nicholasxjy/xue-picker.nvim",
  dependencies = {
    -- Optional: for smart file finding or fff-accelerated grep
    {
      "dmtrKovalenko/fff",
      build = function()
        require("fff.download").download_or_build_binary()
      end,
    },
    -- Optional: icon support
    { "echasnovski/mini.icons" }, -- or "nvim-tree/nvim-web-devicons"
  },
  opts = {
    -- Custom configuration goes here, leave empty to use defaults
  },
  keys = {
    { "<leader><space>", function() require("xue-picker.builtin").smart() end, desc = "Smart find files" },
    { "<leader>ff", function() require("xue-picker.builtin").files() end, desc = "Find files" },
    { "<leader>fg", function() require("xue-picker.builtin").live_grep() end, desc = "Live grep" },
    { "<leader>sw", function() require("xue-picker.builtin").grep_word() end, desc = "Grep word under cursor" },
    { "<leader>fb", function() require("xue-picker.builtin").buffers() end, desc = "Find buffers" },
    { "<leader>fd", function() require("xue-picker.builtin").diagnostics() end, desc = "Find diagnostics" },
    { "<leader>fr", function() require("xue-picker").resume() end, desc = "Resume last picker" },
  },
}
```

### Using Neovim's Built-in `vim.pack`

```lua
vim.pack.add({
  "https://github.com/dmtrKovalenko/fff",
  "https://github.com/nicholasxjy/xue-picker.nvim",
})

-- Run once after installing or updating fff to download/compile its native library:
-- require("fff.download").download_or_build_binary()

require("xue-picker").setup({})

local builtin = require("xue-picker.builtin")
vim.keymap.set("n", "<leader><space>", builtin.smart, { desc = "Smart find files" })
vim.keymap.set("n", "<leader>ff", builtin.files, { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
vim.keymap.set("n", "<leader>sw", builtin.grep_word, { desc = "Grep word under cursor" })
vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Find diagnostics" })
vim.keymap.set("n", "<leader>fr", require("xue-picker").resume, { desc = "Resume last picker" })
```

## Usage

### Commands

The `:XuePicker` user command supports subcommands and tab completion:

```vim
:XuePicker               " Open default picker (smart)
:XuePicker files         " Find files
:XuePicker live_grep     " Live grep
:XuePicker buffers       " List buffers
:XuePicker diagnostics   " Workspace diagnostics
:XuePicker resume        " Resume last closed picker
```

### Builtin Pickers (Lua API)

Call builtins via `require("xue-picker.builtin").<name>(opts)`:

| Builtin | Description & Common Options |
| --- | --- |
| `smart(opts)` | Multi-threaded fuzzy file search and ranking using fff (requires fff). Supports `cwd`, `query`, etc. |
| `files(opts)` | File finder using the built-in high-performance matcher in `cwd`. |
| `live_grep(opts)` | Asynchronous live content search. Supports `query`, `mode = "regex" \| "plain"`, `globs`, `cwd`, etc. |
| `grep_word(opts)` | Live grep using the word under the cursor with literal matching (pass `mode = "regex"` for regex). |
| `buffers(opts)` | Buffer list sorted by recency with a fixed current-buffer header. Use `<C-d>` to delete buffers. |
| `diagnostics(opts)` | Diagnostics list with signs and severity filtering. Supports `scope = "workspace" \| "buffer" \| "cwd"`. |
| `git_files(opts)` | Git tracked files (set `untracked = true` to include untracked files). |
| `oldfiles(opts)` | Previously opened files. Supports `filter = { cwd = true }`. |
| `marks(opts)` | Jump to global and buffer-local marks. |
| `history(opts)` | History picker with `type = "cmd"` (command history) or `type = "search"` (search history). |
| `manpages(opts)` | Asynchronous man page indexing with fuzzy filtering, opens via `:Man`. |

#### Examples

```lua
local builtin = require("xue-picker.builtin")

-- Find files in a specific directory
builtin.files({ cwd = "~/project" })

-- Search only within Lua files, excluding vendor directories
builtin.live_grep({ mode = "plain", globs = { "*.lua", "!vendor/**" } })

-- View warnings and errors in the current buffer
builtin.diagnostics({
  scope = "buffer",
  severity = { min = vim.diagnostic.severity.WARN },
})
```

### Default Keymaps

While a picker is open, the following keymaps are available in the input buffer:

| Keymap | Action |
| --- | --- |
| `<CR>` / `<C-y>` | Accept selection (exports multiple selected items to quickfix) |
| `<Esc>` / `<C-c>` | Close picker |
| `<C-n>` / `<Down>` / `<Tab>` | Next item |
| `<C-p>` / `<Up>` / `<S-Tab>` | Previous item |
| `<C-s>` | Open in horizontal split |
| `<C-v>` | Open in vertical split |
| `<C-t>` | Open in new tab |
| `<C-x>` | Toggle selection (multi-select mode) |
| `<C-a>` | Toggle select all |
| `<C-o>` | Toggle preview window |
| `<C-r>` | Refresh results |
| `<C-d>` | Delete item (in `buffers` picker, closes buffer) |

## Configuration

`xue-picker` works out of the box. All configuration options are optional. See [doc/default-config.lua](doc/default-config.lua) for the complete reference.

```lua
require("xue-picker").setup({
  defaults = {
    -- Keymaps (string or list of strings; set to false or {} to disable)
    keymaps = {
      next = { "<C-n>", "<Down>", "<Tab>" },
      previous = { "<C-p>", "<Up>", "<S-Tab>" },
      accept = { "<CR>", "<C-y>" },
      close = { "<Esc>", "<C-c>" },
      split = "<C-s>",
      vsplit = "<C-v>",
      tab = "<C-t>",
      toggle = "<C-x>",
      toggle_all = "<C-a>",
      delete = "<C-d>",
      preview = "<C-o>",
      refresh = "<C-r>",
    },

    -- Preview configuration
    preview = {
      enabled = false,       -- Enable preview by default (toggle anytime with <C-o>)
      debounce_ms = 60,      -- Preview debounce delay in ms
      max_bytes = 1048576,   -- Maximum file size to preview (default 1 MB)
      max_lines = 2000,      -- Maximum lines to read
    },

    -- Layout options
    layout = {
      height = 0.4,          -- Panel height as a fraction of editor height
      max_height = 18,       -- Maximum panel height in rows
      wide = 100,            -- Column threshold for side-by-side preview
      preview_width = 0.5,   -- Preview width fraction in wide layout
    },

    -- Hints & display
    hint = true,             -- Show bottom action keymap hints
    icons = "auto",          -- "auto" | false | function, auto-detects mini.icons / devicons
    path_format = "filename_first", -- "filename_first" | "relative" | function(item, cwd)

    -- File scanner settings (ripgrep)
    scan = {
      cmd = "rg",
      hidden = true,         -- Include hidden files
      ignore = true,         -- Respect .gitignore
      follow = false,        -- Do not follow symlinks
    },
  },

  -- Picker-specific overrides
  pickers = {
    smart = {
      max_results = 20000,
      debounce_ms = 30,
    },
    live_grep = {
      backend = "auto",      -- "auto" (fff with ripgrep fallback) | "fff" | "ripgrep"
      fallback = true,       -- Fall back to ripgrep on error or timeout
      mode = "regex",        -- "regex" | "plain"
      smartcase = true,
      debounce_ms = 80,
    },
    buffers = {
      sort_lastused = true,  -- Sort by recent use, keep current buffer in header
      ignore_current_buffer = false,
    },
  },

  -- Replace Neovim UI interfaces
  ui = {
    select = false,          -- Set to true to replace vim.ui.select
    input = false,           -- Set to true to replace vim.ui.input
  },
})
```

## Extensions & Integrations

### Lualine Statusline Extension

Add `"xue-picker"` to your lualine extensions to display picker status, result counts, and search state:

```lua
require("lualine").setup({
  extensions = { "xue-picker" },
})
```

### Replace `vim.ui.select` and `vim.ui.input`

Enable them in `setup`:

```lua
require("xue-picker").setup({
  ui = {
    select = true,
    input = true,
  },
})
```

### Custom Pickers

Create custom pickers using `require("xue-picker").pick()`:

```lua
local session = require("xue-picker").pick({
  prompt = "Select Fruit> ",
  items = {
    { id = "1", text = "Apple" },
    { id = "2", text = "Banana" },
    { id = "3", text = "Orange" },
  },
  on_accept = function(items, action, session)
    print("Selected: " .. items[1].text)
  end,
})
```

## License

[MIT](LICENSE)
