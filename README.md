# xue-picker.nvim

基于 Neovim `vim._core.ui2` 命令行区域构建的底部吸附选择器（Picker）。支持智能文件查找、异步实时内容搜索、多选导出 quickfix、预览窗口以及 `vim.ui` 替换。

## 特性

- **底部原生体验**：深度集成 Neovim 0.12+ `ui2`，吸附于命令行区域，布局紧凑流畅。
- **高性能搜索**：
  - 支持调用 [fff](https://github.com/dmtrKovalenko/fff) 原生库进行多线程模糊文件查找与内容检索。
  - 内置独立 matcher 与 ripgrep 兜底机制，兼顾速度与稳定性。
- **丰富的内置选择器**：文件（files / smart）、实时搜索（live_grep / grep_word）、缓冲区（buffers）、诊断（diagnostics）、标记（marks）、历史记录等。
- **功能完备**：支持快捷键交互、多选操作、异步预览、快速跳转 Quickfix、Lualine 状态栏集成与 `vim.ui.select` / `vim.ui.input` 无缝替换。

## 环境要求

- **Neovim 0.12+**（需支持 `vim._core.ui2`）
- **[ripgrep (`rg`)](https://github.com/BurntSushi/ripgrep)**：用于文件扫描及 `live_grep` 内容搜索。
- *(可选)* **[fff](https://github.com/dmtrKovalenko/fff)**：`builtin.smart` 模式及 fff grep 加速所需，需下载/编译其二进制库。
- *(可选)* 图标支持：`mini.icons` 或 `nvim-web-devicons`。

可通过 `:checkhealth xue-picker` 检查环境与依赖状态。

## 安装

### 使用 [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nicholasxjy/xue-picker.nvim",
  dependencies = {
    -- 可选：若使用 smart 查找或 fff grep 加速
    {
      "dmtrKovalenko/fff",
      build = function()
        require("fff.download").download_or_build_binary()
      end,
    },
    -- 可选：图标支持
    { "echasnovski/mini.icons" }, -- 或 "nvim-tree/nvim-web-devicons"
  },
  opts = {
    -- 在此传入自定义配置，留空即使用默认配置
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

### 使用 Neovim 内置 `vim.pack`

```lua
vim.pack.add({
  "https://github.com/dmtrKovalenko/fff",
  "https://github.com/nicholasxjy/xue-picker.nvim",
})

-- 初次安装或更新 fff 后需运行一次以下命令获取原生库：
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

## 使用方法

### 命令调用

支持 `:XuePicker` 用户命令及内置选择器名称自动补全：

```vim
:XuePicker               " 打开默认选择器 (smart)
:XuePicker files         " 查找文件
:XuePicker live_grep     " 实时内容检索
:XuePicker buffers       " 缓冲区列表
:XuePicker diagnostics   " 诊断信息
:XuePicker resume        " 恢复上次关闭的选择器
```

### Lua API 调用与内置选择器

在 Lua 中通过 `require("xue-picker.builtin").<name>(opts)` 调用：

| 选择器名称 | 说明与常用参数 |
| --- | --- |
| `smart(opts)` | 调用 fff 引擎进行多线程模糊文件搜索与排序（需 fff 插件）。支持 `cwd`、`query` 等参数。 |
| `files(opts)` | 使用内置高性能 matcher 在当前工作区（`cwd`）查找文件。 |
| `live_grep(opts)` | 异步文件内容检索。支持 `query`、`mode = "regex" \| "plain"`、`globs`、`cwd` 等。 |
| `grep_word(opts)` | 自动获取光标所在词进行字面检索（支持传入 `mode = "regex"`）。 |
| `buffers(opts)` | 缓冲区选择器，按最近访问排序，当前缓冲区显示在固定头部。支持 `<C-d>` 关闭缓冲区。 |
| `diagnostics(opts)` | LSP/系统诊断列表。支持 `scope = "workspace" \| "buffer" \| "cwd"`、`severity` 过滤与排序。 |
| `git_files(opts)` | 查找 Git 追踪的文件（可配置 `untracked = true` 包含未跟踪文件）。 |
| `oldfiles(opts)` | 查找历史打开过的文件，支持 `filter = { cwd = true }` 限制在当前目录。 |
| `marks(opts)` | 查看和跳转全局及缓冲区 Local Marks。 |
| `history(opts)` | 历史记录选择器，支持 `type = "cmd"`（命令历史）或 `type = "search"`（搜索历史）。 |
| `manpages(opts)` | 异步索引系统 man 手册并进行模糊搜索跳转。 |

#### 调用示例

```lua
local builtin = require("xue-picker.builtin")

-- 在指定目录下查找文件
builtin.files({ cwd = "~/project" })

-- 搜索仅在 .lua 文件中的内容
builtin.live_grep({ mode = "plain", globs = { "*.lua", "!vendor/**" } })

-- 仅查看当前 Buffer 的警告及以上级别诊断
builtin.diagnostics({
  scope = "buffer",
  severity = { min = vim.diagnostic.severity.WARN },
})
```

### 选择器内默认快捷键

选择器窗口打开时，在输入框中可使用以下快捷键操作：

| 快捷键 | 功能 |
| --- | --- |
| `<CR>` / `<C-y>` | 确认选择（多选时自动将所选结果导入 Quickfix 列表并打开） |
| `<Esc>` / `<C-c>` | 关闭当前选择器 |
| `<C-n>` / `<Down>` / `<Tab>` | 移动到下一项 |
| `<C-p>` / `<Up>` / `<S-Tab>` | 移动到上一项 |
| `<C-s>` | 水平分屏打开（Split） |
| `<C-v>` | 垂直分屏打开（Vsplit） |
| `<C-t>` | 新标签页打开（Tab） |
| `<C-x>` | 切换当前项选中状态（多选模式） |
| `<C-a>` | 选中 / 取消选中全部项目 |
| `<C-o>` | 开启 / 关闭预览窗口（Toggle Preview） |
| `<C-r>` | 刷新当前选择器列表 |
| `<C-d>` | 删除项目（在 `buffers` 选择器中用于删除缓冲区） |

## 配置

插件开箱即用，通过 `require("xue-picker").setup(opts)` 可覆盖默认行为。所有配置项均为可选，完整默认配置可参考 [doc/default-config.lua](doc/default-config.lua)。

```lua
require("xue-picker").setup({
  defaults = {
    -- 快捷键设置（可配置为单个按键字符串或按键列表，设为 false 禁用对应操作）
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

    -- 预览窗口配置
    preview = {
      enabled = false,       -- 默认是否开启预览（可通过 <C-o> 随时切换）
      debounce_ms = 60,      -- 预览防抖时间 (ms)
      max_bytes = 1048576,   -- 限制预览文件大小 (默认 1MB)
      max_lines = 2000,      -- 限制最大读取行数
    },

    -- 布局尺寸
    layout = {
      height = 0.4,          -- 高度占窗口比例
      max_height = 18,       -- 最大行数
      wide = 100,            -- 区分宽屏并排预览的宽度阈值
      preview_width = 0.5,   -- 宽屏下预览区域占比
    },

    -- 提示与图标
    hint = true,             -- 底部是否显示操作快捷键提示栏
    icons = "auto",          -- "auto" | false | 函数，自动检测 mini.icons / devicons
    path_format = "filename_first", -- "filename_first" | "relative" | 自定义函数

    -- 文件扫描（rg 配置）
    scan = {
      cmd = "rg",
      hidden = true,         -- 搜索隐藏文件
      ignore = true,         -- 遵循 .gitignore
      follow = false,        -- 是否跟随符号链接
    },
  },

  -- 针对具体 picker 的定制配置
  pickers = {
    smart = {
      max_results = 20000,
      debounce_ms = 30,
    },
    live_grep = {
      backend = "auto",      -- "auto" (优先使用 fff，异常降级至 ripgrep) | "fff" | "ripgrep"
      fallback = true,       -- 发生异常时是否自动回退至 ripgrep
      mode = "regex",        -- "regex" | "plain"
      smartcase = true,
      debounce_ms = 80,
    },
    buffers = {
      sort_lastused = true,  -- 按最近使用排序，当前 buffer 作为常驻标题行
      ignore_current_buffer = false,
    },
  },

  -- 替换 Neovim 原生 UI 接口
  ui = {
    select = false,          -- 设置为 true 替换 vim.ui.select
    input = false,           -- 设置为 true 替换 vim.ui.input
  },
})
```

## 扩展与集成

### Lualine 状态栏扩展

xue-picker 内置了 lualine 扩展，在 picker 展开时会在状态栏显示其当前状态、匹配数量及搜索模式：

```lua
require("lualine").setup({
  extensions = { "xue-picker" },
})
```

### 替换 `vim.ui.select` 与 `vim.ui.input`

只需在 `setup` 中开启对应选项即可：

```lua
require("xue-picker").setup({
  ui = {
    select = true,
    input = true,
  },
})
```

### 自定义 Picker

也可以使用 `require("xue-picker").pick()` 快速构建自定义交互选择器：

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

## 许可证

[MIT](LICENSE)
