# 实测性能与验证记录

采样日期：2026-09-13。机器：Apple M1 Max、64 GiB 内存、Darwin 27.0.0 arm64；Neovim 0.12.5、LuaJIT。使用本地 SSD，默认 4 ms 计算预算、16 ms 绘制间隔。下面是本机采样，不是其他机器的延迟保证。

原始数据：[匹配基准](benchmarks/matcher.json)、[附着 UI 与磁盘基准](benchmarks/ui.json)。

## 匹配计算

`make perf` 固定生成 20,000 和 100,000 个路径候选。查询序列为 `file`、`cmp`、`pkg1`、`component`、`f`、`fi`、`fil`、`file`、`notfound`，重复 5 轮，共 45 次。包含初次准备、普通查询和安全追加查询的缓存缩小；启用文件名与 cwd 加权，关闭 frecency。数据集生成及测试驱动开销不计入查询时间。

| 候选数 | 查询 p50 | 查询 p95 | 最长计算片 | 请求期间 1 ms 心跳最大间隔 |
| --- | ---: | ---: | ---: | ---: |
| 20,000 | 3.76 ms | 14.20 ms | 4.53 ms | 5.60 ms |
| 100,000 | 28.08 ms | 91.81 ms | 11.82 ms | 11.91 ms |

p95 采用 nearest-rank。计算片统计每次 coroutine resume 的时间，包含这段执行中的 JIT/GC；心跳只采样查询正在运行的区间，不把连续生成测试请求的驱动时间误计为 matcher 停顿。时间片间通过定时器返回事件循环，使输入及 I/O 能继续处理。

本次采样满足 2 万/10 万候选查询 p95 ≤50/150 ms、计算停顿 ≤16 ms 的目标。4 ms 是主动让出的预算；LuaJIT、GC 和系统调度可能令单个片超出这个软预算。

## 首屏与刷新

`make perf-ui` 通过 pynvim 启动独立 Neovim，并真实附着 120×40 UI。候选提前生成；“可输入”测到输入 buffer、局部映射及底部面板建立；“恢复首屏”先绘制上次可见候选，再异步刷新。不是把完整刷新完成时间当作首屏。

| 候选数 | 首次面板可输入 | 首次完整结果 | resume 首屏 | resume 完整刷新 |
| --- | ---: | ---: | ---: | ---: |
| 20,000 | 3.66 ms | 32.87 ms | 1.07 ms | 17.23 ms |
| 100,000 | 1.07 ms | 176.78 ms | 0.85 ms | 121.90 ms |

可输入与恢复首屏满足 ≤50 ms 目标。十万候选首次完整准备仍需约 177 ms，这段时间保留可输入面板和加载状态。首屏指标只计 UI 建立及可见缓存，不掩盖后续数据刷新耗时。

另在临时目录中创建 20,000 个真实文件，每个文件两行；创建 fixture 用时 1,564 ms，单独记录，不计入搜索。文件扫描实际使用 `rg --files --null`：

| 项目 | 耗时 |
| --- | ---: |
| 面板可输入 | 1.84 ms |
| 初次扫描、准备及匹配 | 160.09 ms |
| 重新打开，首次绘制缓存结果 | 1.47 ms |
| 重开后的完整重新扫描与刷新 | 261.46 ms |

扫描/刷新包含实际磁盘访问、进程输出解析及匹配，不应直接与纯内存查询 p95 比较。

## grep 与取消

同一 20,000 文件磁盘 fixture；默认结果上限 20,000。查询 `needle` 命中每个文件，`absent-24122` 无结果。下表包含进程启动、磁盘搜索、流式 JSON 解析、分组和匹配状态完成。取消列为启动后立即关闭面板并释放会话资源的响应时间；过期输出由 generation 检查丢弃。

| 请求后端 | 实际后端 | 查询 | 结果数 | 完成时间 | 立即关闭 |
| --- | --- | --- | ---: | ---: | ---: |
| ripgrep | ripgrep | needle | 20,000 | 815.60 ms | 1.12 ms |
| ripgrep | ripgrep | absent-24122 | 0 | 126.34 ms | 0.95 ms |
| auto | ripgrep（fff 不可用） | needle | 20,000 | 832.99 ms | 0.98 ms |
| auto | ripgrep（fff 不可用） | absent-24122 | 0 | 126.49 ms | 0.96 ms |

**fff 原生库冷索引、热索引性能尚未实测。** 本机已有的 `fff.nvim@7066573` checkout 缺少 `content_search()`；实际运行 `XUE_FFF_RTP=/Users/nick/code/fff.nvim make test-fff` 得到明确的 API 不兼容错误。本次没有自动安装或编译替代版本，也没有把受控替身的时间当作 fff 性能。

`make test` 使用受控 fff 替身，但经过真正的独立 headless worker 和异步 RPC；覆盖正常分页、未安装、缺失原生库、API 不兼容、初始化失败/错误通知/超时、请求失败/错误通知/超时、worker 退出、无效返回及异常分页偏移。验证回退会清空并替换结果，当前会话继续使用 rg。共同 fixture 检查 regex/plain、smartcase、Unicode 字节范围和空结果；无效 regex 不采用 literal 结果。

提供现成的兼容 fff 后，可运行：

```sh
XUE_FFF_RTP=/path/to/installed/fff make test-fff
```

该命令不会安装或编译依赖。它创建独立 300 文件 fixture，使用 7 条分页大小对比真实 fff 与 rg，并将冷启动首个请求、复用 worker 后的请求时间写入 `.test-data/fff-real.json`。fff 原生行为与大规模冷/热索引数据仍应据此补充验证。

## 功能与真实 UI

本次已通过：

- `make lint`：StyLua 2.5.2 与所有 Lua 文件语法检查。
- `make test`：51 项集成测试，内部使用独立、附着 UI 的 Neovim；实际验证 `:Man`、分屏、竖分屏、标签打开和 marks 跳转。
- `make differential`：固定 `241e22ccc870e47c78a07264ee7890d355e37102`，22,347 个断言，比较集合、分数、稳定排序、Unicode 高亮、扩展语法及 frecency。
- `make ui`：实际输入、多个映射、滚动、grep 分组、多选 quickfix、预览、120/70/32 列缩放、主题、`cmdheight=0/1`、resume、tab 切换、替换会话、vim.ui 回调，以及含换行的命令历史只回填、不执行。
- help tags 生成与 `:help xue-picker`、`:checkhealth xue-picker`。
- 独立 tmux/TUI 检查：底部区域、文件名/目录格式、预览、消息与缩放、关闭后恢复 `cmdheight=0` 和原窗口。

真实 UI 回归发现并修复了消息浮窗重定位缺少 `relative` 参数的问题；现在同时测试消息出现后缩放和命令行进入时关闭 picker。截图证据以附着 UI 的屏幕文本保存于 `.test-data/ui-*.txt`，终端捕获为 `.test-data/tui-*.txt`；CI 上传这些快照。CI 配置已交付，本次没有向远程推送或运行 GitHub Actions。

## 复现

```sh
make test lint
XUE_REFERENCE=/path/to/minibuffer.nvim make differential
python3 -m venv .test-data/venv
.test-data/venv/bin/pip install -r tests/requirements.txt
make ui PYTHON=.test-data/venv/bin/python
make perf
make perf-ui PYTHON=.test-data/venv/bin/python
```

`NVIM`、`STYLUA`、`PYTHON` 可覆盖工具路径。参考库只作为临时测试 oracle。测试与 worker 使用隔离目录，不改写用户的 Neovim 配置或 frecency 数据。
