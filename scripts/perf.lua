vim.opt.runtimepath:prepend(vim.fn.getcwd())
local uv = vim.uv
local function now()
  return uv.hrtime() / 1e6
end
local function percentile(values, ratio)
  table.sort(values)
  return values[math.ceil(#values * ratio)]
end
local report = { nvim = vim.version(), os = uv.os_uname(), date = os.date("!%FT%TZ"), cases = {} }
for _, count in ipairs({ 20000, 100000 }) do
  local items = {}
  for i = 1, count do
    local path = ("/repo/packages/pkg%03d/src/%s%06d.lua"):format(
      i % 200,
      i % 3 == 0 and "file" or "component",
      i
    )
    items[i] = { id = path, text = path:sub(7), path = path, idx = i }
  end
  local matcher = require("xue-picker.matcher").new({ cwd = "/repo", frecency = false })
  local times, slices, queries = {}, {}, {}
  local gaps, last_tick, active = {}, now(), false
  local heartbeat = uv.new_timer()
  heartbeat:start(1, 1, function()
    local tick = now()
    if active then
      gaps[#gaps + 1] = tick - last_tick
    end
    last_tick = tick
  end)
  require("xue-picker.util").on_slice = function(ms)
    slices[#slices + 1] = ms
  end
  for round = 1, 5 do
    for _, query in ipairs({ "file", "cmp", "pkg1", "component", "f", "fi", "fil", "file", "notfound" }) do
      local start, complete = now(), false
      last_tick, active = start, true
      require("xue-picker.util").work(function(checkpoint)
        return matcher:rank(query, items, checkpoint)
      end, function(_, err)
        assert(not err, err)
        gaps[#gaps + 1] = now() - last_tick
        active = false
        times[#times + 1] = now() - start
        queries[query] = queries[query] or {}
        table.insert(queries[query], now() - start)
        complete = true
      end, 4)
      assert(
        vim.wait(30000, function()
          return complete
        end, 1),
        "benchmark timeout"
      )
    end
  end
  report.cases[#report.cases + 1] = {
    candidates = count,
    query_p50_ms = percentile(times, 0.5),
    query_p95_ms = percentile(times, 0.95),
    max_slice_ms = percentile(slices, 1),
    queries = queries,
    max_heartbeat_gap_ms = #gaps > 0 and percentile(gaps, 1) or 0,
  }
  heartbeat:stop()
  heartbeat:close()
end
vim.fn.mkdir(".test-data", "p")
vim.fn.writefile({ vim.json.encode(report) }, ".test-data/perf.json")
print(vim.inspect(report))
