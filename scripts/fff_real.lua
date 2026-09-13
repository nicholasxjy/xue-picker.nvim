-- Optional validation against an already installed fff. Never installs or builds it.
vim.opt.rtp:prepend(vim.fn.getcwd())
assert(vim.env.XUE_FFF_RTP, "Set XUE_FFF_RTP to an installed fff checkout with its native library")
vim.opt.rtp:append(vim.env.XUE_FFF_RTP)
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
fixture = vim.uv.fs_realpath(fixture)
vim.fn.mkdir(fixture .. "/nested", "p")
vim.fn.writefile({ "directory entry" }, fixture .. "/nested/child.txt")
for i = 1, 300 do
  vim.fn.writefile(
    { "hi🌍 foo Foo", "alpha.beta", "alphaXbeta", "foo", "foo", "foo", "foo" },
    fixture .. "/file" .. i .. ".txt"
  )
end
local opts = require("xue-picker.config").resolve("live_grep", {
  cwd = fixture,
  fallback = false,
  fff = { ready_timeout_ms = 10000, page_size = 7 },
})
local report = {}
local function search(backend, query, mode)
  opts.mode = mode
  local items, complete, failure = {}, false, nil
  local start = vim.uv.hrtime()
  local cancel = require("xue-picker.grep." .. backend).search(opts, query, function(batch, state)
    vim.list_extend(items, batch)
    if state.error then
      failure = state.error
    end
    complete = state.done == true
  end)
  assert(
    vim.wait(30000, function()
      return complete
    end, 1),
    "real fff timeout"
  )
  cancel()
  assert(not failure, failure)
  report[#report + 1] =
    { backend = backend, query = query, mode = mode, count = #items, ms = (vim.uv.hrtime() - start) / 1e6 }
  local out = {}
  for _, item in ipairs(items) do
    out[#out + 1] = { item.path, item.lnum, item.col, item.text, item.ranges }
  end
  table.sort(out, function(a, b)
    return vim.inspect(a) < vim.inspect(b)
  end)
  return out
end
local ok, err = xpcall(function()
  for _, case in ipairs({
    { "foo", "plain" },
    { "Foo", "plain" },
    { "hi🌍", "plain" },
    { "alpha.beta", "regex" },
    { "alpha.beta", "plain" },
    { "absent24122", "regex" },
  }) do
    local expected = search("ripgrep", unpack(case))
    local actual = search("fff", unpack(case))
    assert(vim.deep_equal(expected, actual), "backend mismatch for " .. case[1])
  end
  local fff = require("fff")
  fff.setup({
    base_path = fixture,
    frecency = { enabled = false },
    history = { enabled = false },
    logging = { enabled = false },
  })
  fff.file_search("", { cwd = fixture, max_results = 1, wait_for_index_ms = 0 })
  assert(require("fff.fuzzy").wait_for_initial_scan(10000))
  require("fff.file_picker").setup()
  local ctx = { session = { origin = { buf = vim.api.nvim_get_current_buf() } } }
  for _, case in ipairs({
    { "" },
    { "file12" },
    { "flie12" },
    { "file2 *.txt" },
    { "*.txt !file1*" },
    { "file12.txt:3:2" },
    { "absent24122" },
    { "", { mode = "directories" } },
    { "", { mode = "mixed", max_results = 400 } },
    {
      "file12",
      {
        page = 1,
        max_results = 3,
        current_file = fixture .. "/file12.txt",
        max_threads = 2,
        combo_boost_score_multiplier = 0,
        min_combo_count = 5,
        wait_for_index_ms = 25,
      },
    },
  }) do
    local query = case[1]
    local search_opts = vim.tbl_extend("force", { cwd = fixture, max_results = 17 }, case[2] or {})
    local file_opts = require("xue-picker.config").resolve("smart", search_opts)
    local expected = fff.file_search(query, search_opts)
    local actual, state
    ctx.query = query
    local start = vim.uv.hrtime()
    local cancel = require("xue-picker.sources.fff").search(file_opts, ctx, function(items, info)
      actual, state = items, info
    end)
    assert(
      vim.wait(30000, function()
        return state ~= nil
      end, 1),
      "real fff file_search timeout"
    )
    cancel()
    assert(not state.error, state.error)
    assert(#actual == #expected.items, "file count mismatch for " .. query)
    assert(state.truncated == (expected.total_matched > #expected.items))
    for i, item in ipairs(actual) do
      local relative_path = expected.items[i].relative_path
      assert(
        item.path
          == (relative_path == "" and fixture or require("xue-picker.util").path(relative_path, fixture)),
        "file order mismatch for " .. query
      )
      assert(item.type == expected.items[i].type, "item type mismatch for " .. query)
      assert(item.score == expected.scores[i].total, "score mismatch for " .. query)
      assert(vim.deep_equal(item.ranges, expected.items[i].match_ranges), "highlights mismatch for " .. query)
      if expected.location then
        assert(item.lnum == expected.location.line)
        assert(item.col == (expected.location.col or 1) - 1)
      end
    end
    report[#report + 1] = {
      backend = "fff-files",
      query = query,
      mode = search_opts.mode or "files",
      page = search_opts.page or 0,
      count = #actual,
      ms = (vim.uv.hrtime() - start) / 1e6,
    }
  end
end, debug.traceback)
require("xue-picker.grep.fff").shutdown()
vim.fn.delete(fixture, "rf")
assert(ok, err)
vim.fn.mkdir(".test-data", "p")
vim.fn.writefile({ vim.json.encode(report) }, ".test-data/fff-real.json")
print(vim.inspect(report))
