# xue-picker.nvim

A bottom-docked picker built on Neovim's `vim._core.ui2` command-line area. Supports smart file finding, asynchronous content search, multi-selection quickfix export, toggleable previews, and `vim.ui` adaptations.

Requires **Neovim 0.12+** and **ripgrep (`rg`)**. Automatically initializes `ui2` if it is not already active; reuses existing configuration if it is. `ui2` is an experimental internal API, and capabilities are checked at startup. Run `:checkhealth xue-picker` to inspect dependencies and recent grep fallback reasons.

## Installation

```lua
-- Neovim built-in vim.pack
vim.pack.add({ "https://github.com/nicholasxjy/xue-picker.nvim" })

-- setup() is optional.
require("xue-picker").setup({})

local builtin = require("xue-picker.builtin")
vim.keymap.set("n", "<leader><space>", builtin.smart)
vim.keymap.set("n", "<leader>ff", builtin.files)
vim.keymap.set("n", "<leader>fg", builtin.live_grep)
vim.keymap.set("n", "<leader>fb", builtin.buffers)
vim.keymap.set("n", "<leader>fd", builtin.diagnostics)
vim.keymap.set("n", "<leader>fr", require("xue-picker").resume)
```

With lazy.nvim, add `{ "nicholasxjy/xue-picker.nvim", opts = {} }`. Ready to use once `rg` is installed; the plugin does not automatically install or compile optional dependencies.

## Builtins

`:XuePicker` launches `smart` by default, `:XuePicker <name>` supports name completion, and `:XuePicker resume` is also available. Lua calls follow `require("xue-picker.builtin").<name>(opts)`.

| Name | Default Behavior and Common Options |
| --- | --- |
| `files` | Files in `cwd`, fuzzy and filename weighting, without mixing in history. |
| `smart` | Merges directory files, normal listed buffers, and valid recent files; deduplicates by absolute path, applies cwd/frecency weighting, `filter.cwd=true`. |
| `buffers` | Includes unlisted/unnamed buffers; `%` current, `#` alternate, `+` modified, `RO` read-only; deletion protects unsaved changes by default, explicit `force=true` forces deletion. |
| `live_grep` | regex, smartcase, grouped by file; `backend`, `mode`, `globs`, and `max_results` are configurable. |
| `diagnostics` | Workspace diagnostics, severity-first order, reacts to `DiagnosticChanged`; `scope="buffer"/"cwd"`, `bufnr`, and `severity` follow `vim.diagnostic.get()` semantics. |
| `marks` | Global marks and calling buffer local marks, includes line/column and context, unfolds folds on jump. |
| `oldfiles` | Valid regular files only, preserves recency order; `filter.cwd=true` restricts to cwd. |
| `git_files` | Git tracked files; `untracked=true` includes untracked files as well. |
| `history` | `type="cmd"` puts selection back into the command line for editing; `type="search"` re-executes search. |
| `manpages` | Asynchronous `man -k .`, local fuzzy filtering, opens via `:Man`. |

File and location builtins support multi-selection. Accepting multiple items populates and opens the quickfix list; accepting a single item opens it in the original window, or applies a split/tab action. `:Man` requires a local man database.

```lua
require("xue-picker.builtin").files({ cwd = "~/project" })
require("xue-picker.builtin").diagnostics({ scope = "buffer" })
require("xue-picker.builtin").diagnostics({ severity = { min = vim.diagnostic.severity.WARN } })
require("xue-picker.builtin").live_grep({ mode = "plain", globs = { "*.lua", "!vendor/**" } })
```

`cwd` defaults to the working directory at call time. By default, hidden files are included, ignore rules are respected, `.git` contents are excluded, and symlinks are not followed; spaces, newlines, backslashes, and `$` in paths are treated as literal filenames. The UI displays control characters as visible symbols, while file opening and quickfix export preserve the original paths.

`live_grep` displays each file icon beside its filepath header. Each match starts with separate, right-aligned `line:column` fields before the content; both displayed numbers are 1-based. Field widths use the widest numbers in the current results and remain consistent while scrolling. A custom `path_format` callback formats the filepath header.

## Query Syntax and Sorting

`files`, `smart`, and local filtering use a standalone matcher implementation, differentially verified against `fuzzy.new_snacks` from [`minibuffer.nvim/xue-2@241e22c`](https://github.com/nicholasxjy/minibuffer.nvim/tree/241e22ccc870e47c78a07264ee7890d355e37102).

| Query | Meaning |
| --- | --- |
| `foo bar` | AND, both terms must match. |
| `foo \| bar` | OR within the same group; matches the reference implementation by evaluating alternatives by term entropy. |
| `!test foo` | Excludes items containing `test`, then matches `foo`. |
| `'foo`, `'foo'` | Exact substring, exact word. |
| `^foo`, `lua$` | Prefix and suffix anchors. |
| `file:lua$`, `kind:lua` | Field-targeted filtering; custom fields are also searchable. |
| `foo.lua:10:3` | Matches file and jumps to line 10, byte column 3. |

Default smartcase matches the reference implementation: all-lowercase queries ignore ASCII case, while uppercase characters trigger case sensitivity. Unicode characters are matched and scored by UTF-8 bytes, and highlights never split characters; this is not Unicode case folding. Sorting order is descending score, ascending byte length of logical text, and ascending original `idx`. By default, `history_bonus` and Git modified weighting are disabled. `git.modified_bonus=true` adds 20 bonus points, or a custom score can be provided.

`smart` frecency uses a 30-day half-life, capped at 10,000 entries, lazily and atomically persisted to `stdpath("data")/xue-picker/frecency.json`; corrupted data is automatically ignored. `files` does not use frecency by default.

## Configuration and Keymaps

Precedence: built-in defaults → `setup.defaults` → `setup.pickers[name]` → per-call options. Records are merged field-by-field, while lists are replaced as a whole. See [doc/default-config.lua](doc/default-config.lua) for the full configuration, regenerable from code with `make defaults`.

```lua
require("xue-picker").setup({
  defaults = {
    keymaps = {
      next = { "<C-n>", "<Down>", "<Tab>" },
      previous = { "<C-p>", "<Up>", "<S-Tab>" },
      accept = { "<CR>", "<C-y>" },
      close = { "<Esc>", "<C-c>" },
      split = "<C-s>", vsplit = "<C-v>", tab = "<C-t>",
      toggle = "<C-x>", toggle_all = "<C-a>", delete = "<C-d>",
      preview = "<C-o>", refresh = "<C-r>",
    },
    preview = { enabled = false, max_bytes = 1024 * 1024, max_lines = 2000 },
    layout = { height = 0.4, max_height = 18, wide = 100 },
    icons = "auto", -- false, function, or installed mini.icons / nvim-web-devicons
    hint = true, -- false hides the bottom hint bar and gives its row to results/preview
    path_format = "filename_first", -- "relative" or function(item, cwd)
  },
  pickers = {
    smart = { filter = { cwd = true }, matcher = { frecency = true } },
  },
  ui = { select = false, input = false },
})
```

Each action accepts a string or list of strings; `false` or `{}` disables it. Overriding an action replaces all of its keybindings, while other actions are inherited. Keymaps only take effect in insert and normal modes of the picker input buffer, binding only actions supported by the active picker. Duplicate keys within an action are deduplicated, and conflicts across actions error before opening the picker. Bottom hints use fzf-lua's `:: <ctrl-x> to select|<ctrl-s> to split` style, with separate key, action, and separator highlights. They reflect actual mappings, show aliases separated by `/`, and display only the first key of each action when space is constrained. Open, close, next, previous, preview, and refresh are hidden from hints while their shortcuts remain active. Error hints show only the error message.

Set `defaults.hint = false` to hide the hint bar globally, `pickers.live_grep.hint = false` for a specific picker, or pass `{ hint = false }` to a builtin call. Hints default to `true`. Hiding them frees the row for results or the preview; keybindings remain active.

Previews are disabled by default: side-by-side on wide screens, stacked on narrow screens, and hidden when space is insufficient. Loaded buffers take priority to show unsaved modifications; on-disk files are read asynchronously, capped at 1 MiB and 2,000 lines by default, centered around the target location. Binary and oversized files display an informational notice.

All highlight definitions are exposed in `defaults.highlights` and exported in [doc/default-config.lua](doc/default-config.lua). Defaults link to fzf-lua groups and preserve existing highlight definitions with `default = true`. The target groups must be defined by your colorscheme or fzf-lua; the picker does not load fzf-lua automatically. Error and Git status retain semantic defaults because fzf-lua has no corresponding groups.

| Picker Group | Default Link |
| --- | --- |
| `XuePickerNormal` | `FzfLuaNormal` |
| `XuePickerPrompt` | `FzfLuaFzfPrompt` |
| `XuePickerMatch` | `FzfLuaFzfMatch` |
| `XuePickerIcon` | `FzfLuaNormal` (fallback when the icon provider supplies no group) |
| `XuePickerFilename` | `FzfLuaFilePart` |
| `XuePickerDirectory` | `FzfLuaDirPart` |
| `XuePickerLineNr` | `FzfLuaPathLineNr` |
| `XuePickerColNr` | `FzfLuaPathColNr` |
| `XuePickerSelected` | `FzfLuaFzfCursorLine` |
| `XuePickerMarker` | `FzfLuaFzfMarker` |
| `XuePickerHint` | `FzfLuaHeaderText` |
| `XuePickerHintBind` | `FzfLuaHeaderBind` |
| `XuePickerHintSeparator` | `FzfLuaFzfHeader` |
| `XuePickerCount` | `FzfLuaFzfInfo` |
| `XuePickerError` | `DiagnosticError` |
| `XuePickerGit` | `DiffChange` |
| `XuePickerGroup` | `FzfLuaHeaderText` |
| `XuePickerPreviewLine` | `FzfLuaCursorLine` |
| `XuePickerBorder` | `FzfLuaBorder` |

Override groups using full names and `nvim_set_hl()` definitions:

```lua
require("xue-picker").setup({
  defaults = {
    highlights = {
      XuePickerMatch = { fg = "#ff9e64", bold = true },
      XuePickerSelected = { link = "Visual" },
    },
  },
})
```

Each supplied group definition replaces the inherited definition, including its `link` and `default` fields; other groups are inherited. Picker-specific and per-call `highlights` follow the usual configuration precedence. Definitions apply globally when a picker opens and are reapplied on `ColorScheme` while it is open. Use `default = true` in an override to preserve an existing definition.

File icons use the highlight returned by mini.icons or nvim-web-devicons. A custom `icons(item)` callback can return `icon_text, highlight_group`; returning only text uses `XuePickerIcon`. Filename coloring applies to file rows, displayed location paths, and group headings, with search matches taking priority. Custom `path_format` output is treated as a path; a custom `format` callback controls all of its own spans.

For `files` and `smart`, `path_format = "filename_first"` places the filename and any status markers on the left, followed by a right-aligned directory column. The common right edge comes from the longest visible filename/status/directory row, keeping directories near filenames independently of window width. Alignment accounts for icon and Unicode display widths, with at least two spaces before each directory.

## Optional fff Content Search

```lua
require("xue-picker").setup({
  pickers = {
    live_grep = {
      backend = "auto", -- "auto" | "fff" | "ripgrep"
      fallback = true,
      mode = "regex", -- "regex" | "plain"
      smartcase = true,
      debounce_ms = 80,
      max_results = 20000,
      fff = {
        page_size = 256, time_budget_ms = 8,
        ready_timeout_ms = 150, request_timeout_ms = 1000, idle_timeout_ms = 60000,
      },
      ripgrep = { cmd = "rg", args = {} },
    },
  },
})
```

When using fff, install a version that supports [`content_search()`](https://github.com/dmtrKovalenko/fff#content_searchquery-opts) along with its native library, and ensure its Lua entry point is added to Neovim's `runtimepath`. xue-picker does not invoke fff's picker UI.

`auto` checks the fff interface, native library, and index readiness; it falls back to ripgrep on preparation timeout or unavailability. Explicit `fff` also permits fallback by default; setting `fallback=false` preserves the error panel instead. Sessions that have fallen back stay on ripgrep for the remainder of that session; reopening or resuming checks readiness anew.

The synchronous fff API runs inside an isolated headless Neovim worker, returning paginated results over asynchronous RPC. The worker uses dedicated configuration and cache path `stdpath("cache")/xue-picker/worker/`, loading neither user init nor plugin entry points. Initialization failures, error notifications, API exceptions, request timeouts, and worker exits are all treated as failures; workers are recycled on idle and on exit.

Both backends share identical output conventions: file paths, 1-based line numbers, 0-based UTF-8 byte columns, raw line text, and `[start, end)` byte ranges. Normal empty results, empty queries, and cancellations do not trigger fallback; invalid regex queries produce an explicit error and reject fff's literal fallback results. Fallback clears previous results before rerunning the query.

To preserve equivalent semantics, queries or filter options that fff cannot safely express are delegated to rg: including whitespace, `git:`, `! / * ? { }` (which fff may interpret as constraints), custom globs, non-default scan scopes, and extra ripgrep arguments. When `fallback=false`, an error is raised instead. `ripgrep.args` is intended solely for compatible extra rg flags and must not override `--json`, matching modes, or output contracts.

## Custom Pickers and vim.ui

```lua
local session = require("xue-picker").pick({
  items = {
    { id = "a", text = "Alpha", value = { opaque = 1 } },
    { id = "b", text = "Beta", kind = "example" },
  },
  on_accept = function(items, action, session)
    print(items[1].text)
  end,
  actions = { inspect = function(s) vim.print(s:get_selection()) end },
  keymaps = { inspect = { "<C-g>", "?" } },
})
session:set_query("alp")
session:refresh()
local selection = session:get_selection() -- Multi-selection; returns current item if none selected
session:close()
```

Items should provide stable `id` and `text`; file items add `path`, and location items add `lnum` and `col`. The plugin populates fields like `idx` and `score` internally without shallow- or deep-copying large item arrays. Data refreshes should provide a new array. `format(item, ctx)` returns a string and an optional list of `{ start_byte, end_byte, highlight_group, priority? }`, called only for visible items; span priority defaults to 150. `matcher(query, items, checkpoint)` can replace the default matcher; long loops should invoke `checkpoint()`.

Asynchronous data sources are provided via `source(ctx, emit)`. `ctx` contains `query`, `cwd`, `generation`, and `session`. `emit(items, state)` appends items by default, replaces them when `state.replace=true`, passes `done=true` upon completion, and passes `error` on failure. The source function returns a cancellation callback. Set `live=true` and `debounce_ms` when data needs to re-fetch on query changes; callbacks from stale generations or closed sessions are discarded.

```lua
require("xue-picker").pick({
  live = true,
  debounce_ms = 80,
  source = function(ctx, emit)
    local cancelled = false
    vim.defer_fn(function()
      if not cancelled then
        emit({ { id = "answer", text = ctx.query } }, { replace = true, done = true })
      end
    end, 20)
    return function() cancelled = true end
  end,
})
```

`builtin.ui_select(items, opts, on_choice)` and `builtin.ui_input(opts, on_confirm)` adhere to `vim.ui` callback contracts, preserving original objects and original 1-based indices, invoking the callback exactly once on either accept or cancel. Neither UI replacement participates in `resume`. `ui_select` supports preview buffers provided by `preview_item`; `ui_input` supports `default`, `highlight`, and `completion`, where `<Tab>` fills the active completion candidate when completion is available; `custom`/`customlist` invoke completion functions according to Neovim contracts. Global replacement can be enabled via `setup({ ui = { select = true, input = true } })`.

## Verification and Performance

```sh
make test                     # Lua integration tests in isolated Neovim with UI attached
make lint                     # StyLua 2.5.2 + Lua syntax checks
XUE_REFERENCE=/path/to/minibuffer.nvim make differential
python3 -m venv .test-data/venv
.test-data/venv/bin/pip install -r tests/requirements.txt
make ui PYTHON=.test-data/venv/bin/python
make perf
make perf-ui PYTHON=.test-data/venv/bin/python
XUE_FFF_RTP=/path/to/installed/fff make test-fff  # Optional, requires pre-built native library
```

Full test suites also require a local `man` installation (e.g. `man-db` on Linux) to verify `:Man` navigation actions.

The differential script extracts test oracles from the fixed reference commit into a temporary directory without taking the reference implementation as a runtime dependency. Integration tests verify success, pagination, and failure paths through a real worker/RPC setup using controlled fff test doubles; cold/hot index benchmarks with real fff native libraries require external dependencies. CI runs lint, integration, differential, and attached-UI tests across Neovim stable and nightly, recording UI snapshots and performance JSON.

The file cache keeps up to 3 cwds and 200,000 entries in total, keyed by scan options; reopening initially presents cached results while re-scanning in the background. Lua tasks target a 4 ms time slice, 16 ms render intervals, and 60 ms preview debounce. Machine specifications, methodology, benchmark data, and untested scope are detailed in the [Performance Report](doc/performance.md). These budgets do not constrain disk I/O or external process execution times.

## License

MIT, retaining the original repository license. Implemented independently from minibuffer.nvim; query scoring behavior is benchmarked against the specified commit, and scoring constants match fzf's published algorithm. Optional fff dependencies are subject to their own respective licenses.
