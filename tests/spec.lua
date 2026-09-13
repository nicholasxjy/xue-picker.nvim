local api = vim.api
local B, picker = require("xue-picker.builtin"), require("xue-picker")
local C, U = require("xue-picker.config"), require("xue-picker.util")
local results = {}
local function eq(expected, actual)
  assert(
    vim.deep_equal(expected, actual),
    "expected " .. vim.inspect(expected) .. "\nactual " .. vim.inspect(actual)
  )
end
local function await(fn, message)
  assert(vim.wait(5000, fn, 1), message or "timeout")
end
local function ready(s)
  await(function()
    return not s.loading and not s.searching and not s.preparing and s.started
  end, "session not ready: " .. tostring(s.error))
  assert(not s.error, s.error)
  return s
end
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture .. "/src", "p")
vim.fn.mkdir(fixture .. "/.git", "p")
fixture = vim.uv.fs_realpath(fixture)
local function write(name, lines)
  vim.fn.writefile(lines, fixture .. "/" .. name)
end
write("src/alpha.lua", { "local Foo = '你好 café'", "alpha.beta", "foo Foo", "你好 foo" })
write("beta.txt", { "hello foo", "alphaXbeta", "none" })
write(".hidden", { "foo" })
write("ignored.txt", { "foo" })
write(".ignore", { "ignored.txt" })
write(".git/private", { "foo" })
write("space name.txt", { "foo" })
write("line\nbreak.txt", { "foo" })
write("back\\slash.txt", { "foo" })
write("$HOME.txt", { "foo" })
vim.uv.fs_symlink(fixture .. "/src/alpha.lua", fixture .. "/link.lua")
local function opts(extra)
  return C.merge({
    cwd = fixture,
    git = { enabled = false },
    preview = { debounce_ms = 0 },
    performance = { render_ms = 1 },
  }, extra)
end
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  results[#results + 1] = { name = name, ok = ok, error = err or "" }
  local s = require("xue-picker.session").active
  if s then
    s:close()
  end
  require("xue-picker.grep.fff").shutdown()
  vim.env.XUE_TEST_FFF_MODE = nil
  picker.setup({})
  vim.cmd("stopinsert")
end
test("nested merge, list replacement and precedence", function()
  picker.setup({
    defaults = { keymaps = { next = "j", accept = false }, preview = { max_lines = 7 } },
    pickers = { files = { preview = { max_lines = 8 }, scan = { args = { "--no-ignore" } } } },
  })
  local config = C.resolve("files", { preview = { max_bytes = 9 }, scan = { args = {} } })
  eq("j", config.keymaps.next)
  eq(false, config.keymaps.accept)
  eq(8, config.preview.max_lines)
  eq(9, config.preview.max_bytes)
  eq({}, config.scan.args)
end)
test("mapping deduplication, disabling, conflicts before startup", function()
  local keys = C.bindings(
    { keymaps = { next = { "<C-n>", "<c-n>" }, accept = {}, close = false } },
    { next = true, accept = true, close = true }
  )
  eq({ "<C-n>" }, keys.next)
  eq({}, keys.accept)
  eq(nil, keys.close)
  local old = vim.o.cmdheight
  local ok, err = pcall(picker.pick, { keymaps = { next = "j", previous = "j" } })
  assert(not ok and tostring(err):find("conflict"))
  eq(old, vim.o.cmdheight)
end)
test("custom actions and local keymaps are cleaned", function()
  local value = 0
  local s = ready(picker.pick(opts({
    items = { "foo" },
    actions = {
      ping = function()
        value = value + 1
      end,
    },
    keymaps = { ping = { "z", "Z" } },
  })))
  s:act("ping")
  eq(1, value)
  assert(#api.nvim_buf_get_keymap(s.input_buf, "i") > 0)
  s:close()
  assert(not api.nvim_buf_is_valid(s.input_buf))
end)
test("cancelled matching cannot poison safe query narrowing", function()
  local items = { { text = "foo" }, { text = "file" }, { text = "find" } }
  for i = 4, 200 do
    items[i] = { text = "foo" .. i }
  end
  local ranker = require("xue-picker.matcher").new({ frecency = false })
  ranker:rank("foo", items)
  local co = coroutine.create(function()
    ranker:rank("f", items, function()
      coroutine.yield()
    end)
  end)
  assert(coroutine.resume(co))
  local ranked = ranker:rank("fi", items)
  eq(2, #ranked)
  assert(ranked[1].text == "file" or ranked[1].text == "find")
end)
test("already configured and disabled ui2 settings are preserved", function()
  local core = require("vim._core.ui2")
  core.cfg.msg.msg.timeout = 1732
  local s = ready(picker.pick(opts({ items = { "one" } })))
  eq(1732, core.cfg.msg.msg.timeout)
  s:close()
  core.enable({ enable = false })
  s = ready(picker.pick(opts({ items = { "two" } })))
  assert(core.cfg.enable)
  eq(1732, core.cfg.msg.msg.timeout)
end)
test("files: hidden/ignore/git/symlinks and special filenames", function()
  local s = ready(B.files(opts()))
  local names = {}
  for _, item in ipairs(s.items) do
    names[item.text] = true
  end
  for _, name in ipairs({ ".hidden", "space name.txt", "line\nbreak.txt", "back\\slash.txt", "$HOME.txt" }) do
    assert(names[name], name)
  end
  assert(not names["ignored.txt"] and not names[".git/private"] and not names["link.lua"])
  local special = s.ids[fixture .. "/back\\slash.txt"]
  s:close()
  require("xue-picker.actions").open({ special }, "edit")
  eq(fixture .. "/back\\slash.txt", api.nvim_buf_get_name(0))
end)
test("cache refresh and option keys", function()
  local first = ready(B.files(opts()))
  first:close()
  write("new.txt", { "new" })
  local s = ready(B.files(opts()))
  assert(s.ids[fixture .. "/new.txt"])
  local files = require("xue-picker.sources.files")
  assert(
    files.key(C.resolve("files", opts()))
      ~= files.key(C.resolve("files", opts({ scan = { hidden = false } })))
  )
end)
test("oldfiles validity, deduplication, cwd filtering", function()
  vim.v.oldfiles = { fixture .. "/beta.txt", fixture .. "/beta.txt", fixture .. "/missing", "/etc/hosts" }
  local s = ready(B.oldfiles(opts({ filter = { cwd = true } })))
  eq(1, #s.items)
  eq(fixture .. "/beta.txt", s.items[1].path)
end)
test("smart merges open/recent/directory files by absolute path", function()
  vim.v.oldfiles = { fixture .. "/beta.txt", fixture .. "/src/alpha.lua" }
  vim.cmd({ cmd = "edit", args = { fixture .. "/src/alpha.lua" } })
  local s = ready(B.smart(opts()))
  local count = 0
  for _, item in ipairs(s.items) do
    if item.path == fixture .. "/src/alpha.lua" then
      count = count + 1
      assert(item.info)
    end
  end
  eq(1, count)
  assert(s.ranker.frecency)
end)
test("buffers includes unnamed, status and modified protection", function()
  vim.cmd("enew")
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })
  vim.bo[buf].readonly = true
  local s = ready(B.buffers(opts()))
  local item = s.ids["buffer:" .. buf]
  eq("[No Name]", item.text)
  assert(item.status:find("%+RO", 1, true))
  for i, candidate in ipairs(s.results) do
    if candidate.id == item.id then
      s.index = i
    end
  end
  s:act("delete")
  await(function()
    return not s.loading and not s.searching
  end)
  assert(api.nvim_buf_is_valid(buf) and vim.bo[buf].modified)
  s:close()
  vim.bo[buf].modified = false
  vim.bo[buf].readonly = false
end)
test("buffers force delete is opt-in", function()
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "discard" })
  local s = ready(B.buffers(opts({ force = true })))
  s.selected["buffer:" .. buf] = true
  s:act("delete")
  assert(not api.nvim_buf_is_valid(buf))
end)
test("buffers alternate status comes from invoking window", function()
  local one, two = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(one)
  api.nvim_set_current_buf(two)
  local s = ready(B.buffers(opts()))
  eq("#", s.ids["buffer:" .. one].status:sub(1, 1))
  eq("%", s.ids["buffer:" .. two].status:sub(1, 1))
  s:close()
  api.nvim_buf_delete(one, { force = true })
  api.nvim_buf_delete(two, { force = true })
end)
test("diagnostics scopes, severity order and live update", function()
  local buf = vim.fn.bufadd(fixture .. "/src/alpha.lua")
  vim.fn.bufload(buf)
  local ns = api.nvim_create_namespace("xue-test-diagnostics")
  vim.diagnostic.set(ns, buf, {
    { lnum = 1, col = 2, message = "warning", severity = 2 },
    { lnum = 0, col = 6, message = "error", severity = 1 },
  })
  local s = ready(B.diagnostics(opts({ bufnr = buf })))
  eq(1, s.results[1].severity)
  eq(1, s.results[1].lnum)
  eq(6, s.results[1].col)
  vim.diagnostic.set(ns, buf, { { lnum = 2, col = 0, message = "new", severity = 3 } })
  await(function()
    return #s.results == 1 and s.results[1].text == "new"
  end)
  s:close()
  s = ready(B.diagnostics(opts({ scope = "cwd", severity = { min = 2 } })))
  eq(0, #s.results)
  vim.diagnostic.reset(ns)
end)
test("marks include caller local and global position/context", function()
  vim.cmd({ cmd = "edit", args = { fixture .. "/src/alpha.lua" } })
  api.nvim_buf_set_mark(0, "a", 2, 3, {})
  api.nvim_buf_set_mark(0, "A", 3, 1, {})
  local s = ready(B.marks(opts()))
  eq(2, s.ids["'a"].lnum)
  eq(3, s.ids["'a"].col)
  assert(s.ids["'a"].text:find("alpha.beta", 1, true))
  eq(3, s.ids["'A"].lnum)
  for i, item in ipairs(s.results) do
    if item.id == "'a" then
      s.index = i
    end
  end
  s:accept("edit")
  eq({ 2, 3 }, api.nvim_win_get_cursor(0))
end)
test("git_files tracked/untracked and duplicate staging entries", function()
  vim.system({ "git", "init", "-q", fixture }):wait()
  vim.system({ "git", "-C", fixture, "add", "src/alpha.lua" }):wait()
  local s = ready(B.git_files(opts()))
  eq(1, #s.items)
  s:close()
  s = ready(B.git_files(opts({ untracked = true })))
  assert(#s.items > 1)
end)
test("history source reverse order and search execution", function()
  vim.fn.histadd("cmd", "echo 'one'")
  vim.fn.histadd("cmd", "echo 'two'")
  local s = ready(B.history(opts()))
  eq("echo 'two'", s.results[1].text)
  s:close()
  vim.cmd({ cmd = "edit", args = { fixture .. "/src/alpha.lua" } })
  vim.fn.histadd("search", "alpha")
  s = ready(B.history(opts({ type = "search" })))
  s:accept("edit")
  eq("alpha", vim.fn.getreg("/"))
  eq(2, api.nvim_win_get_cursor(0)[1])
end)
test("manpages asynchronous collection and filtering", function()
  local script = fixture .. "/man-fixture.sh"
  vim.fn.writefile({ "#!/bin/sh", "printf '%s\\n' 'printf (1) - format text' 'ls (1) - list files'" }, script)
  local s = ready(B.manpages(opts({ cmd = { "sh", script } })))
  s:set_query("printf")
  await(function()
    return not s.searching
  end)
  eq(1, #s.results)
  eq("printf", s.results[1].name)
  eq("1", s.results[1].section)
end)
test("manpages accepts through the real Man command", function()
  assert(vim.fn.executable("man") == 1, "Install man-db to run the manpage action test")
  local s = ready(B.manpages(opts({
    source = function(_, emit)
      emit({ { id = "ls(1)", text = "ls", name = "ls", section = "1" } }, { done = true, replace = true })
    end,
  })))
  s:accept("edit")
  await(function()
    return vim.bo.filetype == "man"
  end)
  assert(api.nvim_buf_get_name(0):find("ls", 1, true))
  vim.cmd("enew")
end)
test("ui_select preserves duplicate original objects and index exactly once", function()
  local one, two, calls = { name = "same" }, { name = "same" }, {}
  local s = ready(B.ui_select({ one, two }, {
    format_item = function(x)
      return x.name
    end,
  }, function(value, i)
    calls[#calls + 1] = { value, i }
  end))
  s.index = 2
  s:accept("edit")
  s:close()
  eq(1, #calls)
  assert(calls[1][1] == two)
  eq(2, calls[1][2])
end)
test("ui_select cancellation and replacement callback once", function()
  local count = 0
  local s = B.ui_select({ "a" }, {}, function(value, i)
    assert(value == nil and i == nil)
    count = count + 1
  end)
  picker.pick({ items = {} })
  s:close()
  eq(1, count)
end)
test("ui_select preview_item preserves original value and preview buffer", function()
  local original = { label = "preview" }
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "provided preview" })
  local calls = 0
  local s = ready(B.ui_select({ original }, {
    preview = { enabled = true, debounce_ms = 0 },
    preview_item = function(item)
      assert(item == original)
      calls = calls + 1
      return { buf = buf, pos = { 1, 0 }, pos_end = { 1, 8 } }
    end,
  }, function() end))
  await(function()
    return calls > 0
  end)
  eq(buf, api.nvim_win_get_buf(s.ui.wins.preview))
  s:close()
  assert(api.nvim_buf_is_valid(buf))
  api.nvim_buf_delete(buf, { force = true })
end)
test("ui_input calls its highlight callback", function()
  local called = false
  local s = ready(B.ui_input({
    default = "hello",
    highlight = function(text)
      eq("hello", text)
      called = true
      return { { 0, 5, "Search" } }
    end,
  }, function() end))
  assert(called)
  s:close()
end)
test("ui_input default, empty accept, cancellation and completion", function()
  local calls = {}
  local s = ready(B.ui_input({ default = "hello" }, function(v)
    calls[#calls + 1] = { v }
  end))
  s:accept("edit")
  eq("hello", calls[1][1])
  s = ready(B.ui_input({}, function(v)
    calls[#calls + 1] = { v }
  end))
  s:accept("edit")
  eq("", calls[2][1])
  s = B.ui_input({}, function(v)
    calls[#calls + 1] = { v }
  end)
  s:close()
  eq(nil, calls[3][1])
  eq(3, #calls)
  s = ready(B.ui_input({ default = fixture .. "/src/al", completion = "file" }, function() end))
  assert(#s.results > 0)
  s:act("complete")
  eq(fixture .. "/src/alpha.lua", s.query)
end)
test("ui_input completion inherits configured next keys", function()
  picker.setup({ defaults = { keymaps = { next = { "<C-j>", "<Tab>" } } } })
  local s = ready(B.ui_input({ default = fixture .. "/src/", completion = "file" }, function() end))
  eq({ "<C-j>" }, s.keys.next)
  eq({ "<Tab>" }, s.keys.complete)
end)
test("global vim.ui replacement defaults off and reversible", function()
  local select, input = vim.ui.select, vim.ui.input
  picker.setup({})
  eq(select, vim.ui.select)
  eq(input, vim.ui.input)
  picker.setup({ ui = { select = true, input = true } })
  eq(B.ui_select, vim.ui.select)
  eq(B.ui_input, vim.ui.input)
  picker.setup({})
  eq(select, vim.ui.select)
  eq(input, vim.ui.input)
end)
test("multi-selection quickfix converts zero-based byte columns", function()
  local s = ready(B.files(opts()))
  s.selected[fixture .. "/src/alpha.lua"], s.selected[fixture .. "/beta.txt"] = true, true
  s:accept("edit")
  eq(2, #vim.fn.getqflist())
  eq(1, vim.fn.getqflist()[1].col)
  vim.cmd("cclose")
end)
test("file location query opens and unfolds correct location", function()
  local s = ready(B.files(opts({ query = "alpha.lua:3:2" })))
  eq(1, #s.results)
  s:accept("edit")
  eq({ 3, 1 }, api.nvim_win_get_cursor(0))
end)
test("split, vsplit and tab actions open after restoring the picker", function()
  for _, action in ipairs({ "split", "vsplit", "tab" }) do
    local tab, win = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
    local before = #api.nvim_tabpage_list_wins(tab)
    local s = ready(B.files(opts({ query = "alpha.lua" })))
    s:accept(action)
    eq(fixture .. "/src/alpha.lua", api.nvim_buf_get_name(0))
    assert(s.closed)
    if action == "tab" then
      assert(api.nvim_get_current_tabpage() ~= tab)
      vim.cmd("tabclose")
    else
      eq(before + 1, #api.nvim_tabpage_list_wins(tab))
      vim.cmd("close")
    end
    eq(win, api.nvim_get_current_win())
  end
end)
test("resume restores selection, query, preview and refreshes data", function()
  local s = ready(B.files(opts({ query = "alpha", preview = { enabled = true } })))
  s:act("toggle")
  s:close()
  s = ready(picker.resume())
  eq("alpha", s.query)
  assert(s.preview_enabled)
  assert(s.selected[fixture .. "/src/alpha.lua"])
end)
test("late async deliveries ignored after refresh/close", function()
  local emits, cancels = {}, 0
  local s = picker.pick(opts({
    source = function(_, emit)
      emits[#emits + 1] = emit
      return function()
        cancels = cancels + 1
      end
    end,
  }))
  await(function()
    return #emits == 1
  end)
  s:refresh()
  eq(2, #emits)
  emits[2]({ "new" }, { replace = true, done = true })
  ready(s)
  emits[1]({ "old" }, { replace = true, done = true })
  eq("new", s.results[1].text)
  s:close()
  emits[2]({ "late" }, { replace = true, done = true })
  eq(2, cancels)
end)
test("preview loaded buffer, binary, size limit and stale reads", function()
  local buf = vim.fn.bufadd(fixture .. "/beta.txt")
  vim.fn.bufload(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved preview" })
  local s = ready(B.files(opts({ query = "beta", preview = { enabled = true } })))
  await(function()
    return table
      .concat(api.nvim_buf_get_lines(s.ui.bufs.preview, 0, -1, false))
      :find("unsaved preview", 1, true)
  end)
  s:close()
  vim.bo[buf].modified = false
  api.nvim_buf_delete(buf, { force = true })
  local fd = assert(vim.uv.fs_open(fixture .. "/binary.dat", "w", 384))
  vim.uv.fs_write(fd, "a\0b", 0)
  vim.uv.fs_close(fd)
  s = ready(B.files(opts({ query = "binary", preview = { enabled = true } })))
  await(function()
    return table.concat(api.nvim_buf_get_lines(s.ui.bufs.preview, 0, -1, false)):find("二进制", 1, true)
  end)
  s:close()
  s = ready(B.files(opts({ query = "alpha", preview = { enabled = true, max_bytes = 1 } })))
  await(function()
    return table.concat(api.nvim_buf_get_lines(s.ui.bufs.preview, 0, -1, false)):find("超过", 1, true)
  end)
end)
test("frecency half-life, trim, atomic persistence and corrupt data", function()
  local clock, path = 1700000000, fixture .. "/frecency.json"
  local store = require("xue-picker.frecency").new({
    path = path,
    max_size = 2,
    now = function()
      return clock
    end,
  })
  store:visit({ path = fixture .. "/a" })
  clock = clock + 2592000
  assert(math.abs(store:get({ path = fixture .. "/a" }) - 0.5) < 1e-10)
  store:visit({ path = fixture .. "/b" }, 2)
  store:visit({ path = fixture .. "/c" }, 3)
  assert(store:save())
  eq(2, vim.tbl_count(store.data))
  local saved = require("xue-picker.frecency").new({ path = path })
  for key, value in pairs(store.data) do
    assert(math.abs(value - saved.data[key]) < 1e-5)
  end
  vim.fn.writefile({ "broken" }, path)
  eq({}, require("xue-picker.frecency").new({ path = path }).data)
end)
local function search(backend, query, extra)
  local s = B.live_grep(
    opts(
      C.merge({ backend = backend, query = query, fff = { page_size = 2, ready_timeout_ms = 1000 } }, extra)
    )
  )
  await(function()
    return s.started and not s.loading and not s.searching and not s.preparing
  end)
  return s
end
test("ripgrep regex/plain, smartcase, Unicode byte ranges and no results", function()
  local s = search("ripgrep", "alpha.beta")
  assert(not s.error, s.error)
  eq(2, #s.results)
  s:close()
  s = search("ripgrep", "alpha.beta", { mode = "plain" })
  eq(1, #s.results)
  s:close()
  s = search("ripgrep", "你好")
  eq(2, #s.results)
  for _, item in ipairs(s.results) do
    eq(6, item.ranges[1][2] - item.ranges[1][1])
    eq(item.ranges[1][1], item.col)
  end
  s:close()
  s = search("ripgrep", "Foo")
  eq(2, #s.results)
  s:close()
  s = search("ripgrep", "unlikely-no-results-24122")
  eq(0, #s.results)
  assert(not s.error)
end)
test("invalid regex remains an error with no literal matches", function()
  write("invalid.txt", { "[" })
  local s = search("ripgrep", "[")
  assert(s.error)
  eq(0, #s.results)
end)
test("grep result limit and special names", function()
  local s = search("ripgrep", "foo", { max_results = 3 })
  eq(3, #s.results)
  assert(s.truncated)
  s:close()
  s = search("ripgrep", "foo")
  local found = {}
  for _, item in ipairs(s.results) do
    found[item.path] = true
  end
  assert(found[fixture .. "/line\nbreak.txt"] and found[fixture .. "/back\\slash.txt"])
end)
test("missing fff falls back, missing both remains retryable", function()
  local s = search("auto", "foo")
  eq("ripgrep", s.backend)
  assert(s.fallback)
  s:close()
  s = search("auto", "foo", { ripgrep = { cmd = "xue-nonexistent-rg" } })
  assert(s.error)
  assert(not s.closed)
  s.opts.ripgrep.cmd = "rg"
  s:refresh()
  ready(s)
  assert(#s.results > 0)
end)
vim.opt.rtp:append(vim.fn.getcwd() .. "/tests/fixtures/fff")
test("fff worker pagination shares normalized regex/plain/Unicode contract", function()
  for _, query in ipairs({ "foo", "Foo", "你好", "alpha.beta", "absent24122" }) do
    local rg = search("ripgrep", query)
    assert(not rg.error, rg.error)
    local function compact(items)
      local out = {}
      for _, item in ipairs(items) do
        out[#out + 1] = { item.path, item.lnum, item.col, item.text, item.ranges }
      end
      table.sort(out, function(a, b)
        return vim.inspect(a) < vim.inspect(b)
      end)
      return out
    end
    local expected = compact(rg.results)
    rg:close()
    local fff = search("fff", query, { fallback = false })
    assert(not fff.error, fff.error)
    eq("fff", fff.backend)
    eq(expected, compact(fff.results))
    fff:close()
  end
end)
for _, failure in ipairs({
  "missing_native",
  "incompatible",
  "init_error",
  "notify_init",
  "init_timeout",
  "runtime_error",
  "notify_error",
  "request_timeout",
  "exit",
  "bad_response",
  "bad_page",
}) do
  test("fff failure fallback: " .. failure, function()
    vim.env.XUE_TEST_FFF_MODE = failure
    local s = search(
      "fff",
      "foo",
      { fff = { ready_timeout_ms = failure == "init_timeout" and 30 or 1000, request_timeout_ms = 40 } }
    )
    assert(not s.error, s.error)
    eq("ripgrep", s.backend)
    assert(s.fallback)
    assert(#s.results > 0)
    s:set_query("Foo")
    ready(s)
    eq("ripgrep", s.backend)
  end)
end
test("fff fallback false, unsupported options, invalid regex", function()
  vim.env.XUE_TEST_FFF_MODE = "runtime_error"
  local s = search("fff", "foo", { fallback = false })
  assert(s.error)
  eq("fff", s.backend)
  s:close()
  require("xue-picker.grep.fff").shutdown()
  vim.env.XUE_TEST_FFF_MODE = nil
  s = search("fff", "foo", { globs = { "*.lua" } })
  eq("ripgrep", s.backend)
  assert(#s.results > 0)
  s:close()
  s = search("fff", "[", { fallback = true })
  assert(s.error)
  eq("fff", s.backend)
  eq(0, #s.results)
end)
test("empty queries and normal no-results do not cause fallback", function()
  local s = search("fff", "absent24122")
  assert(not s.error)
  eq("fff", s.backend)
  eq(0, #s.results)
  s:set_query("")
  await(function()
    return s.query == "" and not s.loading
  end)
  eq("fff", s.backend)
end)
test("fff worker cancellation ignores late RPC and idle reclaims", function()
  local s = search("fff", "foo", { fff = { idle_timeout_ms = 10 } })
  eq("fff", s.backend)
  s:set_query("你好")
  s:close()
  await(function()
    return next(require("xue-picker.grep.fff").workers) == nil
  end)
  assert(s.closed)
end)
vim.fn.delete(fixture, "rf")
return results
