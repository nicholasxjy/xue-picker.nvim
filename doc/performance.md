# Measured performance and validation record

Sampled on 2026-09-13 using an Apple M1 Max with 64 GiB RAM, Darwin 27.0.0 arm64, Neovim 0.12.5, and LuaJIT. Storage was a local SSD, with the default 4 ms computation budget and 16 ms render interval. These measurements describe this machine and do not guarantee latency on other systems.

Raw data: [matcher benchmarks](benchmarks/matcher.json) and [attached UI and disk benchmarks](benchmarks/ui.json).

## Matching

`make perf` generates fixed sets of 20,000 and 100,000 path candidates. The query sequence is `file`, `cmp`, `pkg1`, `component`, `f`, `fi`, `fil`, `file`, and `notfound`, repeated five times for 45 queries. Measurements include initial preparation, ordinary queries, and cached candidate narrowing when safely appending to a query. Filename and cwd bonuses are enabled; frecency is disabled. Dataset generation and test-driver overhead are excluded from query time.

| Candidates | Query p50 | Query p95 | Longest computation slice | Largest 1 ms heartbeat gap during a request |
| --- | ---: | ---: | ---: | ---: |
| 20,000 | 3.76 ms | 14.20 ms | 4.53 ms | 5.60 ms |
| 100,000 | 28.08 ms | 91.81 ms | 11.82 ms | 11.91 ms |

p95 uses the nearest-rank method. Computation slices measure each coroutine resume, including JIT and GC work during that execution. Heartbeats are sampled only while a query is running, so time spent generating consecutive test requests is not counted as matcher stalls. Timers return control to the event loop between slices, allowing input and I/O processing to continue.

These samples meet the query p95 targets of ≤50/150 ms for 20,000/100,000 candidates and the computation-stall target of ≤16 ms. The 4 ms budget controls cooperative yielding; LuaJIT, GC, and system scheduling can push individual slices beyond this soft budget.

## Initial display and refresh

`make perf-ui` starts an isolated Neovim through pynvim and attaches a real 120×40 UI. Candidates are generated in advance. “Input ready” measures creation of the input buffer, local mappings, and bottom panel. “Resume first display” renders the previously visible candidates before refreshing asynchronously. Full refresh time is measured separately from the first display.

| Candidates | Initial input ready | Initial complete results | Resume first display | Resume complete refresh |
| --- | ---: | ---: | ---: | ---: |
| 20,000 | 3.66 ms | 32.87 ms | 1.07 ms | 17.23 ms |
| 100,000 | 1.07 ms | 176.78 ms | 0.85 ms | 121.90 ms |

Input readiness and the first resumed display meet the ≤50 ms target. Preparing all 100,000 candidates initially still takes about 177 ms, during which the panel accepts input and displays its loading state. First-display metrics cover UI creation and visible cached results; full refresh costs are reported separately.

A separate temporary fixture contains 20,000 real files with two lines each. Creating it took 1,564 ms, recorded separately and excluded from search time. File scanning uses `rg --files --null`:

| Operation | Time |
| --- | ---: |
| Input ready | 1.84 ms |
| Initial scan, preparation, and matching | 160.09 ms |
| Reopen and first render of cached results | 1.47 ms |
| Complete rescan and refresh after reopening | 261.46 ms |

Scanning and refreshing include actual disk access, process-output parsing, and matching. They should not be compared directly with query p95 for candidates already in memory.

## Grep and cancellation

These measurements use the same 20,000-file disk fixture and the default result limit of 20,000. The query `needle` matches every file; `absent-24122` returns no results. Times include process startup, disk search, streaming JSON parsing, grouping, and completion of matching. The close column measures closing the panel and releasing session resources immediately after startup. Generation checks discard stale output.

| Requested backend | Actual backend | Query | Results | Completion time | Immediate close |
| --- | --- | --- | ---: | ---: | ---: |
| ripgrep | ripgrep | needle | 20,000 | 815.60 ms | 1.12 ms |
| ripgrep | ripgrep | absent-24122 | 0 | 126.34 ms | 0.95 ms |
| auto | ripgrep (fff unavailable) | needle | 20,000 | 832.99 ms | 0.98 ms |
| auto | ripgrep (fff unavailable) | absent-24122 | 0 | 126.49 ms | 0.96 ms |

**Cold- and warm-index performance of the fff native library has not been measured.** The local `fff.nvim@7066573` checkout lacks `content_search()`. Running `XUE_FFF_RTP=/Users/nick/code/fff.nvim make test-fff` produced an explicit API incompatibility error. No replacement version was installed or compiled for this run, and timings from controlled test doubles are not presented as fff performance.

`make test` uses controlled fff doubles through a real isolated headless worker and asynchronous RPC. It covers normal pagination, missing installation or native library, incompatible APIs, initialization failures/error notifications/timeouts, request failures/error notifications/timeouts, worker exits, invalid responses, and invalid pagination offsets. It verifies that fallback clears and replaces results and that the current session continues using rg. Shared fixtures check regex/plain modes, smartcase, Unicode byte ranges, and empty results. Invalid regex queries do not use literal results.

With a compatible fff installation available, run:

```sh
XUE_FFF_RTP=/path/to/installed/fff make test-fff
```

This command does not install or compile dependencies. It creates an isolated 300-file fixture, compares real fff with rg using a page size of seven, and writes timings for the first cold-start request and subsequent requests reusing the worker to `.test-data/fff-real.json`. Native fff behavior and large-scale cold/warm index performance still require further validation.

## Functionality and real UI

The following checks passed in this measurement run:

- `make lint`: StyLua 2.5.2 and syntax checks for all Lua files.
- `make test`: 51 integration tests in isolated Neovim with an attached UI, including actual `:Man`, splits, vertical splits, tabs, and mark jumps.
- `make differential`: 22,347 assertions against the pinned reference `241e22ccc870e47c78a07264ee7890d355e37102`, comparing result sets, scores, stable ordering, Unicode highlights, extended syntax, and frecency.
- `make ui`: actual input, multiple mappings, scrolling, grep groups, multiselect quickfix, preview, resizing to 120/70/32 columns, themes, `cmdheight=0/1`, resume, tab switching, session replacement, vim.ui callbacks, and restoring multiline command history for editing without executing it.
- Help-tag generation, `:help xue-picker`, and `:checkhealth xue-picker`.
- Separate tmux/TUI checks for the bottom panel, filename/directory formatting, preview, messages, resizing, and restoration of `cmdheight=0` and the original window after closing.

Real UI regression testing found and fixed a missing `relative` parameter when repositioning message floats. Tests now cover resizing after a message appears and closing the picker when entering the command line. Attached-UI screen text is saved in `.test-data/ui-*.txt`; terminal captures are saved in `.test-data/tui-*.txt`. CI uploads these snapshots. The CI configuration was delivered, but this measurement run did not push to a remote or run GitHub Actions.

## Reproduction

```sh
make test lint
XUE_REFERENCE=/path/to/minibuffer.nvim make differential
python3 -m venv .test-data/venv
.test-data/venv/bin/pip install -r tests/requirements.txt
make ui PYTHON=.test-data/venv/bin/python
make perf
make perf-ui PYTHON=.test-data/venv/bin/python
```

`NVIM`, `STYLUA`, and `PYTHON` override tool paths. The reference repository is used only as a temporary test oracle. Tests and workers use isolated directories without modifying the user's Neovim configuration or frecency data.
