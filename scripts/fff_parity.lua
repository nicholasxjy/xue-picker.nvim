-- Optional native parity checks against the search and renderer used by find_files.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(assert(vim.env.XUE_FFF_RTP, "Set XUE_FFF_RTP to an installed fff checkout"))
local api = vim.api
local fixture, database = vim.fn.tempname(), vim.fn.tempname()
vim.fn.mkdir(fixture .. "/src", "p")
fixture = vim.uv.fs_realpath(fixture)
local function git(...)
  local result = vim.system({ "git", "-C", fixture, ... }):wait()
  assert(result.code == 0, result.stderr)
end
local function write(path, content)
  vim.fn.writefile({ content }, fixture .. "/" .. path)
end
git("init", "-q")
write("current.lua", "current")
write("other.lua", "other")
write("src/hot.lua", "hot")
git("add", ".")
git("-c", "user.name=XueTest", "-c", "user.email=test@example.test", "commit", "-qm", "fixture")
write("current.lua", "modified")
write("new.lua", "untracked")
write("staged.lua", "staged")
git("add", "staged.lua")
require("fff").setup({
  base_path = fixture,
  lazy_sync = true,
  max_threads = 2,
  frecency = { enabled = true, db_path = database .. "/frecency" },
  history = {
    enabled = true,
    db_path = database .. "/history",
    min_combo_count = 1,
    combo_boost_score_multiplier = 250,
  },
  logging = { enabled = false },
  git = { status_text_color = true },
})
local ok, err = xpcall(function()
  require("fff").file_search("", { cwd = fixture, max_results = 1, wait_for_index_ms = 0 })
  local native = require("fff.fuzzy")
  assert(native.wait_for_initial_scan(10000))
  local file_picker = require("fff.file_picker")
  file_picker.setup()
  for count = 1, 20 do
    native.track_access(fixture .. "/src/hot.lua")
    assert(
      vim.wait(5000, function()
        return native.get_file_access_count(fixture .. "/src/hot.lua") >= count
      end, 1),
      "access history was not persisted"
    )
  end
  native.track_query_completion("lua", fixture .. "/src/hot.lua")
  assert(vim.wait(5000, function()
    file_picker.search_files_paginated("lua", "current.lua", 2, nil, 0, 100)
    return file_picker.get_file_score(1).combo_match_boost > 0
  end, 1))
  vim.cmd({ cmd = "edit", args = { fixture .. "/current.lua" } })
  assert(vim.wait(5000, function()
    return native.get_file_access_count(fixture .. "/current.lua") > 0
  end, 1))
  local opts = require("xue-picker.config").resolve("smart", { cwd = fixture, max_results = 100 })
  local ctx = { session = { origin = { buf = api.nvim_get_current_buf() } } }
  local count = 0
  for _, query in ipairs({ "", "lua", "hot", "current.lua", "absent24122" }) do
    local expected = file_picker.search_files_paginated(query, "current.lua", 2, nil, 0, 100)
    local actual, state
    ctx.query = query
    local cancel = require("xue-picker.sources.fff").search(opts, ctx, function(items, info)
      actual, state = items, info
    end)
    assert(vim.wait(15000, function()
      return state ~= nil
    end, 1))
    cancel()
    assert(not state.error, state.error)
    assert(#actual == #expected, "count mismatch: " .. query)
    for i, item in ipairs(actual) do
      assert(item.text == expected[i].relative_path, "order mismatch: " .. query)
      assert(item.score == file_picker.get_file_score(i).total, "score mismatch: " .. query)
      assert(item.git_status == expected[i].git_status, "git status mismatch")
      count = count + 1
    end
    if query == "" then
      local statuses = {}
      for _, item in ipairs(actual) do
        statuses[item.text] = item.git_status
      end
      assert(statuses["current.lua"] == "modified")
      assert(statuses["new.lua"] == "untracked")
      assert(statuses["staged.lua"] == "staged_new")
    end
  end

  local renderer = require("fff.picker_ui.file_renderer")
  local config = require("fff.conf").get()
  local ns, buf = api.nvim_create_namespace("XueFFFParity"), api.nvim_create_buf(false, true)
  for _, status in ipairs({
    "modified",
    "untracked",
    "staged_new",
    "staged_modified",
    "staged_deleted",
    "deleted",
    "renamed",
    "clean",
    "ignored",
    "unknown",
  }) do
    for _, current in ipairs({ false, true }) do
      for _, marked in ipairs({ false, true }) do
        local item = { id = "file", name = "file.lua", relative_path = "dir/file.lua", git_status = status }
        local context = {
          config = config,
          cursor = current and 1 or 2,
          win_width = 80,
          max_path_width = 78,
          query = "",
          selected_files = marked and { [item.relative_path] = true } or {},
          format_file_display = function()
            return "file.lua", "dir"
          end,
        }
        local line = renderer.render_line(item, context, 1)[1]
        api.nvim_buf_set_lines(buf, 0, -1, false, { line })
        api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        renderer.apply_highlights(item, context, 1, buf, ns, 1, line)
        local expected, priority = nil, 0
        for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
          local details = mark[4]
          if details.sign_text and details.priority > priority then
            expected, priority = details, details.priority
          end
        end
        local style = require("xue-picker.fff").style(item, {
          opts = { git = { enabled = true } },
          selected = marked and { file = true } or {},
        }, current)
        assert(
          style.prefix
            == (expected and vim.trim(expected.sign_text) or "")
              .. string.rep(" ", expected and vim.trim(expected.sign_text) ~= "" and 1 or 2),
          "sign mismatch: " .. status
        )
        if expected then
          assert(style.spans[1][3] == expected.sign_hl_group, "highlight mismatch: " .. status)
        else
          assert(#style.spans == 0)
        end
        count = count + 1
      end
    end
  end
  api.nvim_buf_delete(buf, { force = true })
  print(
    "Native find_files parity: "
      .. count
      .. " ranked items/sign cases; shared history, current-file penalty, Git metadata and renderer highlights OK"
  )
end, debug.traceback)
require("xue-picker.grep.fff").shutdown()
vim.fn.delete(fixture, "rf")
vim.fn.delete(database, "rf")
assert(ok, err)
