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
local function highlighted(s, group, kind)
  s.ui:render()
  local buf = s.ui.bufs[kind or "list"]
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local spans = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local details = mark[4]
    if details.hl_group == group then
      spans[#spans + 1] = {
        text = lines[mark[2] + 1]:sub(mark[3] + 1, details.end_col),
        priority = details.priority,
      }
    end
  end
  return spans
end
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture .. "/src", "p")
vim.fn.mkdir(fixture .. "/.git", "p")
fixture = vim.uv.fs_realpath(fixture)
local function write(name, lines)
  vim.fn.writefile(lines, fixture .. "/" .. name)
end
write("src/alpha.lua", { "local Foo = 'hi🌍 café'", "alpha.beta", "foo Foo", "hi🌍 foo" })
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
test("every builtin and vim.ui picker uses the shared leading gutter", function()
  local function check(s)
    ready(s)
    local prefix = s.opts.name == "buffers" and "XuePickerBuffer" or "XuePicker"
    eq({ { text = "▌", priority = 150 } }, highlighted(s, prefix .. "Pointer"))
    assert(#highlighted(s, prefix .. "Gutter") > 0, s.opts.name)
    if s.actions.toggle then
      s:act("toggle")
      eq({ { text = "┃", priority = 150 } }, highlighted(s, prefix .. "Marker"))
    end
    s:move(1)
    eq(2, s.index)
    eq({ { text = "▌", priority = 150 } }, highlighted(s, prefix .. "Pointer"))
    s:close()
  end
  for _, name in ipairs(B.names) do
    local items = {}
    for i, text in ipairs({ "alpha", "beta", "gamma" }) do
      items[i] = {
        id = tostring(i),
        text = text,
        path = fixture .. "/src/alpha.lua",
        bufnr = api.nvim_get_current_buf(),
        lnum = i,
        col = 0,
        severity = 1,
      }
    end
    check(B[name](opts({
      icons = false,
      multiline = false,
      layout = { height = 10 },
      source = function(_, emit)
        emit(items, { replace = true, done = true })
      end,
    })))
  end
  check(picker.pick(opts({ items = { "alpha", "beta", "gamma" }, multiselect = true })))
  check(B.ui_select({ "alpha", "beta", "gamma" }, opts(), function() end))
  check(B.ui_input(opts({ completion = "file", default = fixture .. "/" }), function() end))
end)
test("custom formatters retain byte highlights behind the configurable gutter", function()
  picker.setup({ defaults = { pointer = "▶", gutter = "·", marker = "✓" } })
  eq("▶", C.resolve("buffers", {}).pointer)
  local marks = { { 0, #"🌟", "Search", 180 } }
  local s = ready(picker.pick(opts({
    items = { "one", "two" },
    multiselect = true,
    highlights = { XuePickerPointer = { fg = "#123456" }, XuePickerGutter = { fg = "#abcdef" } },
    format = function(item, ctx)
      eq(ctx.session.ui.list_width - 2, ctx.width)
      return "🌟" .. item.text, marks
    end,
  })))
  eq({ { text = "▶", priority = 150 } }, highlighted(s, "XuePickerPointer"))
  eq({ { text = "·", priority = 150 } }, highlighted(s, "XuePickerGutter"))
  eq({ { text = "🌟", priority = 180 }, { text = "🌟", priority = 180 } }, highlighted(s, "Search"))
  eq({ { 0, #"🌟", "Search", 180 } }, marks)
  eq(0x123456, api.nvim_get_hl(0, { name = "XuePickerPointer" }).fg)
  eq(0xabcdef, api.nvim_get_hl(0, { name = "XuePickerGutter" }).fg)
  s:act("toggle")
  eq({ { text = "✓", priority = 150 } }, highlighted(s, "XuePickerMarker"))
  s:close()
  vim.cmd("colorscheme default")
end)
test("statusline state follows async results, selection, refresh and close", function()
  eq(nil, picker.status())
  eq("", picker.statusline())
  local states = {}
  local event = api.nvim_create_autocmd("User", {
    pattern = "XuePickerUpdate",
    callback = function()
      states[#states + 1] = picker.status() or false
    end,
  })
  local emit
  local s = picker.pick(opts({
    name = "custom",
    hint = false,
    multiselect = true,
    source = function(_, deliver)
      emit = deliver
    end,
  }))
  eq("custom", picker.status().name)
  eq(0, picker.status().index)
  assert(picker.status().loading)
  eq("XuePicker custom · 0/0 · Loading", picker.statusline())
  await(function()
    return emit ~= nil
  end)
  emit({ "alpha", "beta", "gamma" }, { done = true, replace = true })
  ready(s)
  s.ui:render()
  eq("XuePicker custom · 3/3", picker.statusline())
  local count = #states
  s.ui:render()
  eq(count, #states)
  local state = picker.status()
  state.name = "changed"
  eq("custom", picker.status().name)
  s:move(1)
  s:act("toggle")
  s.ui:render()
  eq(2, picker.status().index)
  eq(1, states[#states].selected)
  s:set_query("alpha")
  ready(s)
  s.ui:render()
  eq("alpha", states[#states].query)
  eq(1, picker.status().count)
  eq("XuePicker custom · 1/3 · 1 selected", picker.statusline())
  s:refresh()
  assert(picker.status().loading)
  emit({}, { done = true, replace = true, error = "source failed", truncated = true, backend = "test" })
  await(function()
    return not s.loading and not s.searching
  end)
  s.ui:render()
  eq("XuePicker custom · 0/0 · 1 selected · test · Failed · Truncated", picker.statusline())
  s:close()
  eq(false, states[#states])
  eq(nil, picker.status())
  eq("", picker.statusline())
  count = #states
  s:close()
  eq(count, #states)
  api.nvim_del_autocmd(event)
end)
test("native statusline restores options on close, replacement and resume", function()
  local laststatus, global, win = vim.o.laststatus, vim.go.statusline, api.nvim_get_current_win()
  local local_statusline = vim.wo[win].statusline
  vim.go.statusline, vim.wo[win].statusline = "GLOBAL %f", "ORIGINAL %l"
  for _, value in ipairs({ 0, 1, 2, 3 }) do
    vim.o.laststatus = value
    local s = ready(picker.pick(opts({ items = { "alpha", "beta" }, name = "100%#ErrorMsg# café\n" })))
    eq(3, vim.o.laststatus)
    local rendered = api.nvim_eval_statusline(vim.wo[s.ui.wins.input].statusline, {
      winid = s.ui.wins.input,
      maxwidth = 120,
    }).str
    assert(rendered:find("100%#ErrorMsg# café", 1, true), rendered)
    eq("GLOBAL %f", vim.go.statusline)
    eq("ORIGINAL %l", vim.wo[win].statusline)
    local replacement = ready(picker.pick(opts({ items = { "new" } })))
    assert(s.closed)
    replacement:close()
    eq(value, vim.o.laststatus)
    local resumed = ready(picker.resume())
    eq(3, vim.o.laststatus)
    resumed:close()
    eq(value, vim.o.laststatus)
    eq("GLOBAL %f", vim.go.statusline)
    eq("ORIGINAL %l", vim.wo[win].statusline)
  end
  vim.o.laststatus, vim.go.statusline, vim.wo[win].statusline = laststatus, global, local_statusline
end)
test("statusline opt-out preserves options and still publishes state", function()
  local laststatus = vim.o.laststatus
  vim.o.laststatus = 2
  picker.setup({ defaults = { statusline = false } })
  local s = ready(picker.pick(opts({ items = { "one" } })))
  eq(2, vim.o.laststatus)
  eq(1, picker.status().count)
  assert(not vim.wo[s.ui.wins.input].statusline:find("xue-picker", 1, true))
  s:close()
  eq(2, vim.o.laststatus)
  s = ready(picker.pick(opts({ items = { "one" }, statusline = true })))
  eq(3, vim.o.laststatus)
  vim.o.laststatus = 1
  s:close()
  eq(1, vim.o.laststatus)
  vim.o.laststatus = laststatus
end)
test("statusline restores after input window closure and failed opening", function()
  local laststatus = vim.o.laststatus
  vim.o.laststatus = 2
  local s = ready(picker.pick(opts({ items = { "one" } })))
  api.nvim_win_close(s.ui.wins.input, true)
  assert(s.closed)
  eq(2, vim.o.laststatus)
  eq(nil, picker.status())
  local ok = pcall(
    picker.pick,
    opts({
      highlight = function()
        error("statusline test render failure")
      end,
    })
  )
  assert(not ok)
  eq(2, vim.o.laststatus)
  eq(nil, picker.status())
  vim.o.laststatus = laststatus
end)
test("highlight overrides replace links and default flags at each configuration layer", function()
  picker.setup({
    defaults = { highlights = { XuePickerMatch = { fg = "#123456", bold = true } } },
    pickers = { files = { highlights = { XuePickerMatch = { link = "Search" } } } },
  })
  eq({ fg = "#123456", bold = true }, C.resolve("buffers", {}).highlights.XuePickerMatch)
  eq({ link = "Search" }, C.resolve("files", {}).highlights.XuePickerMatch)
  local s = ready(B.files(opts({ highlights = { XuePickerMatch = { fg = "#abcdef" } } })))
  eq({ fg = "#abcdef" }, s.opts.highlights.XuePickerMatch)
  eq(C.defaults.highlights.XuePickerPrompt, s.opts.highlights.XuePickerPrompt)
  eq(0xabcdef, api.nvim_get_hl(0, { name = "XuePickerMatch" }).fg)
  vim.cmd("colorscheme default")
  eq(0xabcdef, api.nvim_get_hl(0, { name = "XuePickerMatch" }).fg)
  eq("FzfLuaFzfMatch", C.defaults.highlights.XuePickerMatch.link)
  s:close()
  api.nvim_set_hl(0, "XuePickerMatch", { link = "FzfLuaFzfMatch" })
end)
test("default highlight links preserve theme overrides and follow target colors", function()
  api.nvim_set_hl(0, "XuePickerPrompt", { fg = "#123456" })
  api.nvim_set_hl(0, "FzfLuaFzfMatch", { fg = "#abcdef" })
  local s = ready(picker.pick(opts({ items = { "foo" } })))
  eq(0x123456, api.nvim_get_hl(0, { name = "XuePickerPrompt" }).fg)
  eq("FzfLuaFzfMatch", api.nvim_get_hl(0, { name = "XuePickerMatch" }).link)
  eq(0xabcdef, api.nvim_get_hl(0, { name = "XuePickerMatch", link = false }).fg)
  api.nvim_set_hl(0, "FzfLuaFzfMatch", { fg = "#654321" })
  eq(0x654321, api.nvim_get_hl(0, { name = "XuePickerMatch", link = false }).fg)
  s:close()
  vim.cmd("colorscheme default")
end)
test("filename and icon spans handle Unicode, escaped characters and match priority", function()
  local name = "hi🌍\ncafé.lua"
  for _, path_format in ipairs({ "filename_first", "relative" }) do
    local s = ready(picker.pick(opts({
      items = { U.file(fixture .. "/src/" .. name, fixture) },
      query = "café",
      path_format = path_format,
      icons = function()
        return "◆ ", "Special"
      end,
    })))
    eq({ { text = "◆ ", priority = 150 } }, highlighted(s, "Special"))
    eq({ { text = U.clean(name), priority = 100 } }, highlighted(s, "XuePickerFilename"))
    eq({ { text = "src/", priority = 150 } }, highlighted(s, "XuePickerDirectory"))
    local matches = highlighted(s, "XuePickerMatch")
    assert(#matches > 0)
    for _, match in ipairs(matches) do
      assert(match.priority > 100 and ("café"):find(match.text, 1, true))
    end
    s:close()
  end
  local s = ready(picker.pick(opts({
    items = { U.file(fixture .. "/src/" .. name, fixture) },
    path_format = function()
      return "x.lua"
    end,
    icons = false,
  })))
  eq({ { text = "x.lua", priority = 100 } }, highlighted(s, "XuePickerFilename"))
  eq({}, highlighted(s, "XuePickerDirectory"))
end)
test("files and smart align directories to the longest visible row independently of window width", function()
  for _, builtin in ipairs({ B.files, B.smart }) do
    local item = U.file(fixture .. "/dir🌍\t/alpha.lua", fixture)
    item.status = "+"
    local second_directory = "very-long-directory/🌍/"
    local second = U.file(fixture .. "/" .. second_directory .. "b.lua", fixture)
    local s = ready(builtin(opts({
      query = "🌍",
      sort = false,
      source = function(_, emit)
        emit({ item, second }, { replace = true, done = true })
      end,
      icons = function()
        return "📄 ", "Special"
      end,
    })))
    s.git_status[item.path] = " M"
    local directory = "dir🌍⇥/"
    local longest_width = vim.fn.strdisplaywidth("▌ 📄 b.lua  " .. second_directory)
    local baseline
    for _, width in ipairs({ 120, 60, 32, 8 }) do
      s.ui.list_width = width
      eq({
        { text = directory, priority = 150 },
        { text = second_directory, priority = 150 },
      }, highlighted(s, "XuePickerDirectory"))
      eq({
        { text = "alpha.lua", priority = 100 },
        { text = "b.lua", priority = 100 },
      }, highlighted(s, "XuePickerFilename"))
      eq({ { text = "   M", priority = 150 } }, highlighted(s, "XuePickerGit"))
      local lines = api.nvim_buf_get_lines(s.ui.bufs.list, 0, 2, false)
      eq(longest_width, vim.fn.strdisplaywidth(lines[1]))
      eq(longest_width, vim.fn.strdisplaywidth(lines[2]))
      eq(directory, lines[1]:sub(-#directory))
      assert(lines[2]:find("b.lua  " .. second_directory, 1, true))
      baseline = baseline or lines
      eq(baseline, lines)
      local matches = highlighted(s, "XuePickerMatch")
      assert(#matches > 0)
      for _, match in ipairs(matches) do
        eq("🌍", match.text)
      end
    end
    s:set_query("alpha")
    ready(s).ui:render()
    local line = api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1]
    eq("▌ 📄 alpha.lua  +   M  " .. directory, line)
    s.opts.path_format = "relative"
    s.ui:render()
    line = api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1]
    assert(line:find(directory .. "alpha.lua", 1, true))
    s:close()
  end
end)
test("icons use mini.icons, devicons and custom callback highlight groups", function()
  local mini, devicons = package.loaded["mini.icons"], package.loaded["nvim-web-devicons"]
  local ok, err = xpcall(function()
    for _, provider in ipairs({ "mini.icons", "nvim-web-devicons" }) do
      package.loaded["mini.icons"], package.loaded["nvim-web-devicons"] = nil, nil
      package.loaded[provider] = {
        [provider == "mini.icons" and "get" or "get_icon"] = function()
          return "◆", "Special"
        end,
      }
      local s = ready(picker.pick(opts({ items = { U.file(fixture .. "/beta.txt", fixture) } })))
      eq({ { text = "◆ ", priority = 150 } }, highlighted(s, "Special"))
      eq({ { text = "beta.txt", priority = 100 } }, highlighted(s, "XuePickerFilename"))
      s.opts.icons = function()
        return "◇ "
      end
      eq({ { text = "◇ ", priority = 150 } }, highlighted(s, "XuePickerIcon"))
      eq({}, highlighted(s, "Special"))
      s.opts.icons = false
      eq({}, highlighted(s, "XuePickerIcon"))
      eq({}, highlighted(s, "Special"))
      s:close()
    end
  end, debug.traceback)
  package.loaded["mini.icons"], package.loaded["nvim-web-devicons"] = mini, devicons
  assert(ok, err)
end)
test("location paths and group headings highlight filenames without coloring content as a path", function()
  for _, group in ipairs({ false, true }) do
    local s = ready(picker.pick(opts({
      items = { { path = fixture .. "/src/alpha.lua", text = "content/with/slashes", lnum = 1 } },
      group = group,
      icons = false,
    })))
    eq({ { text = "alpha.lua", priority = 100 } }, highlighted(s, "XuePickerFilename"))
    eq(
      { { text = "src/", priority = 150 } },
      highlighted(s, group and "XuePickerGroup" or "XuePickerDirectory")
    )
    s:close()
  end
end)
test("live_grep renders header icons and leading aligned locations with accurate match spans", function()
  local items = {
    {
      id = "a",
      path = fixture .. "/src/alpha.lua",
      lnum = 2,
      col = 8,
      text = "\thi🌍 match",
      ranges = { { 8, 13 } },
    },
    {
      id = "b",
      path = fixture .. "/src/alpha.lua",
      lnum = 24,
      col = 9,
      text = "         match",
      ranges = { { 9, 14 } },
    },
    {
      id = "c",
      path = fixture .. "/z.txt",
      lnum = 300,
      col = 119,
      text = string.rep(" ", 119) .. "match",
      ranges = { { 119, 124 } },
    },
  }
  local s = ready(B.live_grep(opts({
    query = "match",
    source = function(_, emit)
      emit(items, { replace = true, done = true })
    end,
    icons = function()
      return "◆ ", "Special"
    end,
  })))
  eq({ { text = "◆ ", priority = 150 }, { text = "◆ ", priority = 150 } }, highlighted(s, "Special"))
  local lines = api.nvim_buf_get_lines(s.ui.bufs.list, 0, 5, false)
  eq("  ◆ src/alpha.lua", lines[1])
  eq("▌ " .. "  2:  9  " .. U.clean(items[1].text), lines[2])
  eq("▌ " .. " 24: 10  " .. items[2].text, lines[3])
  eq("  ◆ z.txt", lines[4])
  eq("▌ " .. "300:120  " .. items[3].text, lines[5])
  eq(
    { { text = "  2", priority = 150 }, { text = " 24", priority = 150 }, { text = "300", priority = 150 } },
    highlighted(s, "XuePickerLineNr")
  )
  eq(
    { { text = "  9", priority = 150 }, { text = " 10", priority = 150 }, { text = "120", priority = 150 } },
    highlighted(s, "XuePickerColNr")
  )
  local matches = highlighted(s, "XuePickerMatch")
  eq(15, #matches)
  for _, match in ipairs(matches) do
    assert(("match"):find(match.text, 1, true))
  end
  eq("FzfLuaPathLineNr", api.nvim_get_hl(0, { name = "XuePickerLineNr" }).link)
  eq("FzfLuaPathColNr", api.nvim_get_hl(0, { name = "XuePickerColNr" }).link)
  s.opts.path_format = function(item)
    return "custom/" .. vim.fs.basename(item.path)
  end
  s.opts.icons = false
  s.ui:render()
  eq({}, highlighted(s, "Special"))
  local custom = api.nvim_buf_get_lines(s.ui.bufs.list, 0, 2, false)
  eq("  custom/alpha.lua", custom[1])
  eq(lines[2], custom[2])
end)
test("live_grep location widths follow streaming results and stay aligned across scrolling", function()
  local emit_rows
  local first = { id = "first", path = fixture .. "/alpha.lua", lnum = 2, text = "match" }
  local s = ready(B.live_grep(opts({
    query = "match",
    icons = false,
    source = function(_, emit)
      emit_rows = emit
      emit({ first }, { replace = true, done = true })
    end,
  })))
  s.ui.list_height = 2
  eq({ { text = "2", priority = 150 } }, highlighted(s, "XuePickerLineNr"))
  eq({ { text = "1", priority = 150 } }, highlighted(s, "XuePickerColNr"))
  emit_rows(
    { { id = "last", path = fixture .. "/z.lua", lnum = 1000, col = 99, text = "match" } },
    { done = true }
  )
  ready(s)
  eq({ { text = "   2", priority = 150 } }, highlighted(s, "XuePickerLineNr"))
  eq({ { text = "  1", priority = 150 } }, highlighted(s, "XuePickerColNr"))
  s:act("next")
  eq({ { text = "1000", priority = 150 } }, highlighted(s, "XuePickerLineNr"))
  eq({ { text = "100", priority = 150 } }, highlighted(s, "XuePickerColNr"))
  s:act("previous")
  eq({ { text = "   2", priority = 150 } }, highlighted(s, "XuePickerLineNr"))
  emit_rows({ first }, { replace = true, done = true })
  ready(s)
  eq({ { text = "2", priority = 150 } }, highlighted(s, "XuePickerLineNr"))
  eq({ { text = "1", priority = 150 } }, highlighted(s, "XuePickerColNr"))
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
test("hint visibility respects configuration precedence and keeps errors and mappings available", function()
  picker.setup({ defaults = { hint = false }, pickers = { files = { hint = true } } })
  local s = ready(picker.pick(opts({ items = { "one", "two" } })))
  eq(nil, s.ui.wins.hint)
  eq(s.ui.height - 1, api.nvim_win_get_height(s.ui.wins.list))
  s:act("next")
  eq(2, s.index)
  eq({}, highlighted(s, "XuePickerHint", "hint"))
  s.results, s.error = {}, "visible error"
  s.ui:render()
  assert(api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1]:find("visible error", 1, true))
  s:close()
  s = ready(B.files(opts()))
  assert(api.nvim_win_is_valid(s.ui.wins.hint))
  eq(s.ui.height - 2, api.nvim_win_get_height(s.ui.wins.list))
  s:close()
  s = ready(B.files(opts({ hint = false })))
  eq(nil, s.ui.wins.hint)
end)
test("hint visibility reclaims preview space and preserves buffers across layout changes", function()
  local s = ready(B.files(opts({
    hint = false,
    layout = { height = 10, wide = 200, min_preview = 2 },
    preview = { enabled = true },
  })))
  eq(nil, s.ui.wins.hint)
  eq(4, api.nvim_win_get_height(s.ui.wins.preview))
  s.opts.hint = true
  s.ui:layout()
  s.ui:render()
  local hint_win, hint_buf = s.ui.wins.hint, s.ui.bufs.hint
  assert(api.nvim_win_is_valid(hint_win))
  eq(3, api.nvim_win_get_height(s.ui.wins.preview))
  s.opts.hint, s.opts.layout.wide = false, 40
  s.ui:layout()
  s.ui:render()
  assert(not api.nvim_win_is_valid(hint_win) and api.nvim_buf_is_valid(hint_buf))
  eq(9, api.nvim_win_get_height(s.ui.wins.list))
  eq(9, api.nvim_win_get_height(s.ui.wins.preview))
  s.opts.hint = true
  s.ui:layout()
  s.ui:render()
  eq(hint_buf, api.nvim_win_get_buf(s.ui.wins.hint))
  s:close()
  assert(not api.nvim_buf_is_valid(hint_buf))
end)
test("fzf headers sort individual bindings and color only key text inside brackets", function()
  local s = ready(picker.pick(opts({
    items = { "foo" },
    actions = { custom = function() end, ["more🌟"] = function() end, preview = function() end },
    keymaps = {
      custom = { "Z", "z" },
      ["more🌟"] = "<M-j>",
    },
  })))
  s.ui.width = 1000
  eq({
    { text = "Z", priority = 150 },
    { text = "alt-j", priority = 150 },
    { text = "z", priority = 150 },
  }, highlighted(s, "XuePickerHintBind", "hint"))
  eq({
    { text = "custom", priority = 150 },
    { text = "more🌟", priority = 150 },
    { text = "custom", priority = 150 },
  }, highlighted(s, "XuePickerHint", "hint"))
  eq(
    "  :: <Z> to custom|<alt-j> to more🌟|<z> to custom",
    api.nvim_buf_get_lines(s.ui.bufs.hint, 0, 1, false)[1]
  )
  eq(
    { ":: ", "<", "> to ", "|", "<", "> to ", "|", "<", "> to " },
    vim.tbl_map(function(span)
      return span.text
    end, highlighted(s, "XuePickerHintSeparator", "hint"))
  )
  s.ui.width = 22
  s.ui:render()
  eq("  :: <Z> to custom|··", api.nvim_buf_get_lines(s.ui.bufs.hint, 0, 1, false)[1])
  eq({ "Z", "z" }, s.keys.custom)
  for _, name in ipairs({ "accept", "close", "next", "previous", "preview", "refresh" }) do
    assert(s.keys[name] and #s.keys[name] > 0, name .. " shortcut must remain active")
  end
end)
test("hint clipping preserves Unicode and the colors under fzf ellipsis cells", function()
  local hints = require("xue-picker.hints")
  local state = { opts = {}, keys = { split = { "<C-s>" }, vsplit = { "<C-v>" }, toggle = { "<C-x>" } } }
  local text, spans = hints.render(state, 32)
  eq("  :: <ctrl-s> to split|<ctrl-··", text)
  eq("XuePickerHintBind", spans[#spans - 1][3])
  eq("XuePickerHintSeparator", spans[#spans][3])
  state.keys = { ["more🌟"] = { "<M-j>", "z" } }
  text, spans = hints.render(state, 24)
  eq("  :: <alt-j> to more··", text)
  eq("XuePickerHint", spans[#spans - 1][3])
  eq("XuePickerHintSeparator", spans[#spans][3])
  state.keys = { ["café é🌟"] = { "z", "<M-j>" } }
  for width = 1, 60 do
    text, spans = hints.render(state, width)
    assert(vim.fn.strdisplaywidth(text) <= math.max(0, width - 1), text)
    eq(text, vim.fn.iconv(text, "utf-8", "utf-8"))
    for _, span in ipairs(spans) do
      assert(span[1] < span[2] and span[2] <= #text)
      eq(text:sub(span[1] + 1, span[2]), vim.fn.iconv(text:sub(span[1] + 1, span[2]), "utf-8", "utf-8"))
    end
  end
  eq("", hints.render({ opts = {}, keys = {} }, 32))
  eq(
    "  :: <ctrl-d> to close",
    hints.render({ opts = { name = "buffers" }, keys = { delete = { "<C-d>" } } }, 80)
  )
end)
test("hint defaults match fzf-lua dark and light colors without loading fzf-lua", function()
  local background = vim.o.background
  for _, name in ipairs({ "FzfLuaHeaderBind", "FzfLuaHeaderText", "FzfLuaFzfHeader" }) do
    api.nvim_set_hl(0, name, {})
  end
  for _, case in ipairs({ { "dark", "BlanchedAlmond", "Brown1" }, { "light", "MediumSpringGreen", "Brown4" } }) do
    vim.o.background = case[1]
    local s = ready(picker.pick(opts({ items = { "one" } })))
    eq(
      api.nvim_get_color_by_name(case[2]),
      api.nvim_get_hl(0, { name = "XuePickerHintBind", link = false }).fg
    )
    eq(api.nvim_get_color_by_name(case[3]), api.nvim_get_hl(0, { name = "XuePickerHint", link = false }).fg)
    s:close()
  end
  vim.o.background = background
  api.nvim_set_hl(0, "FzfLuaHeaderBind", { fg = "#123456", bold = true })
  api.nvim_set_hl(0, "FzfLuaHeaderText", { fg = "#abcdef" })
  api.nvim_set_hl(0, "FzfLuaFzfHeader", { fg = "#654321" })
  local s = ready(picker.pick(opts({ items = { "one" } })))
  for name, target in pairs({
    XuePickerHintBind = "FzfLuaHeaderBind",
    XuePickerHint = "FzfLuaHeaderText",
    XuePickerHintSeparator = "FzfLuaFzfHeader",
  }) do
    eq(target, api.nvim_get_hl(0, { name = name }).link)
  end
  api.nvim_set_hl(0, "XuePickerHintBind", { fg = "#fedcba" })
  s.ui.highlights(s.opts)
  eq(0xfedcba, api.nvim_get_hl(0, { name = "XuePickerHintBind" }).fg)
  s:close()
  s = ready(picker.pick(opts({ highlights = { XuePickerHint = { fg = "#345678" } } })))
  eq(0x345678, api.nvim_get_hl(0, { name = "XuePickerHint" }).fg)
  s:close()
  vim.cmd("colorscheme default")
end)
test("error hints show the message while recovery shortcuts remain active and hidden", function()
  local s = ready(picker.pick(opts({ items = { "foo" } })))
  s.error, s.ui.width = "Error\nretry failed", 1000
  eq({}, highlighted(s, "XuePickerHintBind", "hint"))
  eq({}, highlighted(s, "XuePickerHint", "hint"))
  eq({ { text = "Error↵retry failed", priority = 150 } }, highlighted(s, "XuePickerError", "hint"))
  eq("  :: Error↵retry failed", api.nvim_buf_get_lines(s.ui.bufs.hint, 0, 1, false)[1])
  assert(#s.keys.close > 0 and #s.keys.refresh > 0)
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
  local s = ready(B.buffers(opts({ sort_lastused = false })))
  local item = s.ids["buffer:" .. buf]
  eq("[No Name]", item.text)
  eq("%a=+", item.status)
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
  eq(two, s.buffer_header.bufnr)
  eq("%", s.buffer_header.status:sub(1, 1))
  eq(nil, s.ids["buffer:" .. two])
  eq(one, s.results[1].bufnr)
  s:close()
  api.nvim_buf_delete(one, { force = true })
  api.nvim_buf_delete(two, { force = true })
end)
test("buffers render fixed current header, aligned flags, icons and saved line numbers", function()
  local origin, hidden = api.nvim_get_current_buf(), vim.o.hidden
  vim.o.hidden = true
  local current, other, unnamed =
    api.nvim_create_buf(true, false), api.nvim_create_buf(true, false), api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(current, fixture .. "/buffers/café🌟.lua")
  api.nvim_buf_set_name(other, fixture .. "/buffers/nested/other.lua")
  api.nvim_set_current_buf(other)
  api.nvim_buf_set_lines(other, 0, -1, false, { "one", "two", "three" })
  api.nvim_win_set_cursor(0, { 3, 1 })
  vim.bo[other].readonly = true
  api.nvim_set_current_buf(current)
  api.nvim_buf_set_lines(current, 0, -1, false, { "one", "two" })
  api.nvim_win_set_cursor(0, { 2, 0 })
  vim.bo[current].modified = false
  local ids = { [current] = true, [other] = true, [unnamed] = true }
  local s = ready(B.buffers(opts({
    icons = function()
      return "λ ", "Search"
    end,
    filter = {
      fn = function(item)
        return ids[item.bufnr]
      end,
    },
  })))
  eq(current, s.buffer_header.bufnr)
  eq(other, s.results[1].bufnr)
  eq(2, #s.results)
  eq(nil, s.ids["buffer:" .. current])
  eq("%a  ", s.buffer_header.status)
  eq("#h=+", s.results[1].status)
  eq(3, s.results[1].buffer_lnum)
  eq(nil, s.results[1].lnum)
  s.ui:render()
  local lines = api.nvim_buf_get_lines(s.ui.bufs.list, 0, -1, false)
  local width = require("xue-picker.buffers").number_width(s)
  eq(
    ("  [%d]%s %%a    λ buffers/café🌟.lua:2"):format(
      current,
      string.rep(" ", width - #tostring(current) + 1)
    ),
    lines[1]
  )
  eq(
    ("▌ [%d]%s #h=+  λ buffers/nested/other.lua:3"):format(
      other,
      string.rep(" ", width - #tostring(other) + 1)
    ),
    lines[2]:gsub(" +$", "")
  )
  eq({ { text = "%", priority = 150 } }, highlighted(s, "XuePickerBufferCurrent"))
  eq({ { text = "#", priority = 150 } }, highlighted(s, "XuePickerBufferAlternate"))
  eq(
    { { text = "2", priority = 150 }, { text = "3", priority = 150 } },
    highlighted(s, "XuePickerBufferLineNr")
  )
  local pinned = lines[1]
  s:set_query("other")
  ready(s)
  s.ui:render()
  eq(1, #s.results)
  eq(pinned, api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1])
  assert(#highlighted(s, "XuePickerBufferMatch") > 0)
  s:act("toggle_all")
  eq(1, #s:get_selection())
  eq(nil, s.selected[s.buffer_header.id])
  s.ui.list_width = 32
  s.ui:render()
  local narrow = api.nvim_buf_get_lines(s.ui.bufs.list, 1, 2, false)[1]
  assert(narrow:find("··", 1, true) and narrow:find("other", 1, true), narrow)
  assert(vim.fn.strdisplaywidth(narrow) <= 31)
  eq(
    "other",
    table.concat(vim.tbl_map(function(span)
      return span.text
    end, highlighted(s, "XuePickerBufferMatch")))
  )
  s.ui.list_width = s.ui.width
  s:set_query("no matching buffer")
  ready(s)
  s.ui:render()
  eq(0, #s.results)
  eq(pinned, api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1])
  s:set_query("other")
  ready(s)
  s.opts.layout.height = 3
  s.ui:layout()
  s.ui:render()
  assert(api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1]:find("other.lua", 1, true))
  s:close()
  s = ready(picker.resume())
  eq(current, s.buffer_header.bufnr)
  eq("other", s.query)
  s:accept("edit")
  eq(other, api.nvim_get_current_buf())
  eq({ 3, 1 }, api.nvim_win_get_cursor(0))
  s = ready(picker.resume())
  eq(other, s.buffer_header.bufnr)
  eq(nil, s.selected["buffer:" .. other])
  s:close()
  api.nvim_set_current_buf(origin)
  for buf in pairs(ids) do
    api.nvim_buf_delete(buf, { force = true })
  end
  vim.o.hidden = hidden
end)
test("buffer visibility, filename-only matching and header options follow fzf-lua", function()
  local origin = api.nvim_get_current_buf()
  local unlisted = api.nvim_create_buf(false, false)
  api.nvim_buf_set_name(unlisted, fixture .. "/hidden-buffer.lua")
  local unloaded = vim.fn.bufadd(fixture .. "/unloaded-buffer.lua")
  vim.bo[unloaded].buflisted = true
  local ids = { [origin] = true, [unlisted] = true, [unloaded] = true }
  local extra = { icons = false, filter = {
    fn = function(item)
      return ids[item.bufnr]
    end,
  } }
  local s = ready(B.buffers(opts(extra)))
  assert(s.buffer_header and s.ids["buffer:" .. unloaded])
  eq(nil, s.ids["buffer:" .. unlisted])
  s:close()
  s = ready(
    B.buffers(opts(C.merge(extra, { show_unlisted = true, show_unloaded = false, sort_lastused = false })))
  )
  eq(nil, s.buffer_header)
  assert(s.ids["buffer:" .. origin] and s.ids["buffer:" .. unlisted])
  eq(nil, s.ids["buffer:" .. unloaded])
  s:close()
  s = ready(B.buffers(opts(C.merge(extra, { ignore_current_buffer = true, filename_only = true }))))
  eq(nil, s.buffer_header)
  eq(nil, s.ids["buffer:" .. origin])
  s.ui:render()
  local text = api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1]
  assert(text:find("unloaded-buffer.lua", 1, true) and not text:find(".lua:", 1, true))
  eq("unloaded-buffer.lua", s.results[1].text)
  s:close()
  api.nvim_buf_delete(unlisted, { force = true })
  api.nvim_buf_delete(unloaded, { force = true })
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
test("diagnostics sort controls severity, provider and custom order while filtering", function()
  local buf = vim.fn.bufadd(fixture .. "/src/alpha.lua")
  vim.fn.bufload(buf)
  local ns = api.nvim_create_namespace("xue-test-diagnostic-sort")
  vim.diagnostic.set(ns, buf, {
    { lnum = 0, col = 0, message = "token", severity = 2 },
    { lnum = 1, col = 0, message = "long token here", severity = 1 },
    { lnum = 2, col = 0, message = "token hint", severity = 4 },
    { lnum = 3, col = 0, message = "token info", severity = 3 },
  })
  local function severities(items)
    return vim.tbl_map(function(item)
      return item.severity
    end, items)
  end
  local provider = severities(vim.diagnostic.get(buf))
  for _, case in ipairs({
    { true, { 1, 2, 3, 4 } },
    { 1, { 1, 2, 3, 4 } },
    { false, provider },
    { "reverse", { 4, 3, 2, 1 } },
    { 2, { 4, 3, 2, 1 } },
    { "2", { 4, 3, 2, 1 } },
    {
      function(values, config)
        eq(buf, config.bufnr)
        table.sort(values, function(a, b)
          return a.lnum > b.lnum
        end)
        return values
      end,
      { 3, 4, 1, 2 },
    },
  }) do
    picker.setup({ pickers = { diagnostics = { sort = case[1] } } })
    local s = ready(B.diagnostics(opts({ bufnr = buf })))
    eq(case[2], severities(s.results))
    s:set_query("token")
    eq(case[2], severities(ready(s).results))
    s:close()
  end
  picker.setup({ pickers = { diagnostics = { sort = false } } })
  local s = ready(B.diagnostics(opts({ bufnr = buf, sort = true })))
  eq({ 1, 2, 3, 4 }, severities(s.results))
  s:close()
  vim.diagnostic.reset(ns)
end)
test("diagnostics match fzf-lua signs, source, location, message and code highlights", function()
  local buf = vim.fn.bufadd(fixture .. "/src/alpha.lua")
  vim.fn.bufload(buf)
  local ns = api.nvim_create_namespace("xue-test-diagnostic-style")
  local original_signs = vim.diagnostic.config().signs
  vim.diagnostic.config({ signs = { text = { [1] = "🛑" } } })
  vim.diagnostic.set(ns, buf, {
    {
      lnum = 0,
      col = 6,
      message = "  bad café\tvalue\nnext line  ",
      severity = 1,
      source = "lua_ls",
      code = "E001",
    },
  })
  local s = ready(B.diagnostics(opts({ bufnr = buf, query = "café" })))
  s.ui:render()
  eq({
    "▌ 🛑 [lua_ls] alpha.lua src:1:7:",
    "▌      bad café⇥value",
    "▌ next line [E001]",
    "",
  }, api.nvim_buf_get_lines(s.ui.bufs.list, 0, 4, false))
  eq(
    { { text = "🛑", priority = 150 }, { text = "[lua_ls]", priority = 150 } },
    highlighted(s, "XuePickerDiagnosticError")
  )
  eq({ { text = "alpha.lua", priority = 100 } }, highlighted(s, "XuePickerFilename"))
  eq({ { text = "src", priority = 150 } }, highlighted(s, "XuePickerDirectory"))
  eq({ { text = "1", priority = 150 } }, highlighted(s, "XuePickerLineNr"))
  eq({ { text = "7", priority = 150 } }, highlighted(s, "XuePickerColNr"))
  eq({ { text = "café", priority = 150 } }, highlighted(s, "XuePickerMatch"))
  eq({ { text = " [E001]", priority = 150 } }, highlighted(s, "XuePickerDiagnosticCode"))
  local selected = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(s.ui.bufs.list, -1, 0, -1, { details = true })) do
    if mark[4].line_hl_group == "XuePickerSelected" then
      selected[#selected + 1] = mark[2]
    end
  end
  eq({ 0, 1, 2 }, selected)
  eq(3, #highlighted(s, "XuePickerPointer"))
  s:act("toggle")
  eq({ { text = "┃", priority = 150 } }, highlighted(s, "XuePickerMarker"))
  for _, level in ipairs({ "Error", "Warn", "Info", "Hint" }) do
    eq("DiagnosticSign" .. level, api.nvim_get_hl(0, { name = "XuePickerDiagnostic" .. level }).link)
  end
  eq("Comment", api.nvim_get_hl(0, { name = "XuePickerDiagnosticCode" }).link)
  s.ui.list_width = 18
  s.ui:render()
  for _, line in ipairs(api.nvim_buf_get_lines(s.ui.bufs.list, 0, -1, false)) do
    assert(vim.fn.strdisplaywidth(line) <= 18)
  end
  local matches = vim.tbl_map(function(span)
    return span.text
  end, highlighted(s, "XuePickerMatch"))
  eq("café", table.concat(matches))
  s:close()
  s = ready(
    B.diagnostics(opts({ bufnr = buf, path_format = "relative", multiline = false, diag_icons = false }))
  )
  s.ui:render()
  eq(
    "▌ E [lua_ls] src/alpha.lua:1:7: bad café⇥value [E001]",
    api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1]
  )
  eq({
    { text = "E", priority = 150 },
    { text = "[lua_ls]", priority = 150 },
    { text = "src/alpha.lua", priority = 150 },
  }, highlighted(s, "XuePickerDiagnosticError"))
  s:close()
  s = ready(B.diagnostics(opts({
    bufnr = buf,
    multiline = false,
    diag_source = false,
    diag_code = false,
    signs = { Error = { text = "!", texthl = "Special" } },
  })))
  eq({ { text = "!", priority = 150 } }, highlighted(s, "Special"))
  eq({}, highlighted(s, "XuePickerDiagnosticCode"))
  assert(not api.nvim_buf_get_lines(s.ui.bufs.list, 0, 1, false)[1]:find("lua_ls", 1, true))
  s:close()
  vim.diagnostic.config({ signs = original_signs })
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
test("opening files lists new and existing buffers before BufEnter", function()
  for _, existing in ipairs({ false, true }) do
    local name = existing and "tabline-existing.txt" or "tabline-new [file].txt"
    write(name, { "tabline regression" })
    local path = fixture .. "/" .. name
    local buf = existing and vim.fn.bufadd(path) or nil
    if buf then
      assert(not vim.bo[buf].buflisted)
    end
    local listed_on_enter
    local event = api.nvim_create_autocmd("BufEnter", {
      callback = function(ev)
        if api.nvim_buf_get_name(ev.buf) == path then
          listed_on_enter = vim.bo[ev.buf].buflisted
        end
      end,
    })
    local s = ready(picker.pick(opts({ items = { { path = path, bufnr = buf, text = name } } })))
    s:accept("edit")
    api.nvim_del_autocmd(event)
    eq(path, api.nvim_buf_get_name(0))
    assert(vim.bo.buflisted and listed_on_enter)
    local opened = api.nvim_get_current_buf()
    local buffers = ready(B.buffers(opts()))
    eq(opened, buffers.buffer_header.bufnr)
    buffers:close()
    api.nvim_buf_delete(opened, { force = true })
    vim.fn.delete(path)
  end
end)
test("opening a special buffer preserves its unlisted status", function()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  require("xue-picker.actions").open({ { bufnr = buf } }, "edit")
  eq(buf, api.nvim_get_current_buf())
  assert(not vim.bo[buf].buflisted)
  api.nvim_buf_delete(buf, { force = true })
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
    vim.bo[vim.fn.bufnr(fixture .. "/src/alpha.lua")].buflisted = false
    s:accept(action)
    eq(fixture .. "/src/alpha.lua", api.nvim_buf_get_name(0))
    assert(vim.bo.buflisted)
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
    return table.concat(api.nvim_buf_get_lines(s.ui.bufs.preview, 0, -1, false)):find("Binary", 1, true)
  end)
  s:close()
  s = ready(B.files(opts({ query = "alpha", preview = { enabled = true, max_bytes = 1 } })))
  await(function()
    return table.concat(api.nvim_buf_get_lines(s.ui.bufs.preview, 0, -1, false)):find("exceeds", 1, true)
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
  s = search("ripgrep", "hi🌍")
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
test("fff worker waits for the native index without initializing picker UI", function()
  vim.env.XUE_TEST_FFF_MODE = "uninitialized_picker_ui"
  local s = search("fff", "foo", { fallback = false })
  assert(not s.error, s.error)
  eq("fff", s.backend)
  assert(#s.results > 0)
end)
test("fff worker pagination shares normalized regex/plain/Unicode contract", function()
  for _, query in ipairs({ "foo", "Foo", "hi🌍", "alpha.beta", "absent24122" }) do
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
  "scan_timeout",
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
  s:set_query("hi🌍")
  s:close()
  await(function()
    return next(require("xue-picker.grep.fff").workers) == nil
  end)
  assert(s.closed)
end)
vim.fn.delete(fixture, "rf")
return results
