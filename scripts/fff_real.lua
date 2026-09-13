-- Optional validation against an already installed fff. Never installs or builds it.
vim.opt.rtp:prepend(vim.fn.getcwd())
assert(vim.env.XUE_FFF_RTP, "Set XUE_FFF_RTP to an installed fff checkout with its native library")
vim.opt.rtp:append(vim.env.XUE_FFF_RTP)
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
fixture = vim.uv.fs_realpath(fixture)
for i = 1, 300 do
  vim.fn.writefile(
    { "你好 foo Foo", "alpha.beta", "alphaXbeta", "foo", "foo", "foo", "foo" },
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
    { "你好", "plain" },
    { "alpha.beta", "regex" },
    { "alpha.beta", "plain" },
    { "absent24122", "regex" },
  }) do
    local expected = search("ripgrep", unpack(case))
    local actual = search("fff", unpack(case))
    assert(vim.deep_equal(expected, actual), "backend mismatch for " .. case[1])
  end
end, debug.traceback)
require("xue-picker.grep.fff").shutdown()
vim.fn.delete(fixture, "rf")
assert(ok, err)
vim.fn.mkdir(".test-data", "p")
vim.fn.writefile({ vim.json.encode(report) }, ".test-data/fff-real.json")
print(vim.inspect(report))
