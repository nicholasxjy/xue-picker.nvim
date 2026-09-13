-- Deterministic optional-backend double. Runs through the real worker/RPC path.
local M = {}
local function mode()
  return vim.env.XUE_TEST_FFF_MODE
end
function M.setup(config)
  M.config, vim.g.fff = config, config
end
function M.file_search(query, opts)
  -- Programmatic initialization does not initialize fff's picker UI state.
  if mode() == "uninitialized_picker_ui" and opts.wait_for_index_ms > 0 and not M.picker_initialized then
    vim.notify("FFF file_search: timeout waiting for index scan", vim.log.levels.ERROR)
    return { items = {} }
  end
  if mode() == "init_timeout" then
    vim.uv.sleep(500)
  end
  if mode() == "init_error" then
    error("fixture init failed")
  end
  if mode() == "notify_init" then
    vim.notify("fixture init notification", vim.log.levels.ERROR)
  end
  M.index_started = true
  if opts.mode then
    assert(
      opts.mode == "files" or opts.mode == "directories" or opts.mode == "mixed",
      "invalid file search mode"
    )
    if mode() == "file_error" or query == "file_error" then
      error("fixture file search failed")
    elseif mode() == "file_notify" then
      vim.notify("fixture file notification", vim.log.levels.ERROR)
    elseif mode() == "file_bad_response" then
      return {}
    elseif mode() == "file_timeout" or query == "slow" then
      vim.uv.sleep(200)
    end
    -- Deliberately ranked and typo-matched by the backend, never by the picker.
    local items = {
      { type = "file", relative_path = "beta.txt", git_status = "modified", match_ranges = { { 0, 4 } } },
      {
        type = "file",
        relative_path = "src/alpha.lua",
        git_status = "untracked",
        match_ranges = { { 4, 9 } },
      },
    }
    local directory = { type = "directory", relative_path = "src/" }
    local root = { type = "directory", relative_path = "" }
    if opts.mode == "directories" then
      items = { directory, root }
    elseif opts.mode == "mixed" then
      items[#items + 1] = directory
      items[#items + 1] = root
    end
    local location
    if query == "alpah *.lua !test/" then
      items = { items[2] }
    elseif query == "alpha.lua:3:2" then
      items, location = { items[2] }, { line = 3, col = 2 }
    elseif query == "absent24122" then
      items = {}
    elseif query == "current" then
      assert(opts.current_file == "src/alpha.lua", "invoking file must use fff's relative-path format")
      items = { items[1] }
    elseif query == "ranking_config" then
      assert(M.config.max_threads == 6)
      assert(M.config.follow_symlinks)
      assert(M.config.frecency.enabled and M.config.history.enabled)
      assert(M.config.frecency.db_path == opts.cwd .. "/ranking-frecency")
      assert(M.config.history.db_path == opts.cwd .. "/ranking-history")
      assert(M.config.history.min_combo_count == 8)
      assert(M.config.history.combo_boost_score_multiplier == 250)
    elseif query == "options" then
      assert(opts.max_threads == 2, "missing max_threads")
      assert(opts.current_file == opts.cwd .. "/beta.txt", "missing current_file override")
      assert(opts.combo_boost_score_multiplier == 0, "missing combo boost override")
      assert(opts.min_combo_count == 5, "missing min_combo_count")
      assert(opts.wait_for_index_ms == 25, "missing wait_for_index_ms")
      assert(opts.ready_timeout_ms == nil and opts.query == nil, "picker options leaked to fff")
    end
    local total = #items
    local first = opts.page * opts.max_results + 1
    items = vim.list_slice(items, first, first + opts.max_results - 1)
    return {
      items = items,
      scores = { { total = 7 }, { total = 999 } },
      total_matched = total,
      location = location,
    }
  end
  return { items = {} }
end
function M.content_search(query, opts)
  if mode() == "exit" then
    vim.cmd("qa!")
  end
  if mode() == "request_timeout" then
    vim.uv.sleep(500)
  end
  if mode() == "runtime_error" then
    error("fixture runtime failed")
  end
  if mode() == "notify_error" then
    vim.notify("fixture error notification", vim.log.levels.ERROR)
    return { items = {}, next_file_offset = 0 }
  end
  if mode() == "bad_response" then
    return {}
  end
  if mode() == "bad_page" then
    return { items = {}, next_file_offset = -1 }
  end
  local args = { "rg", "--json", "--hidden", "--glob", "!.git/**" }
  args[#args + 1] = opts.smart_case and "--smart-case" or "--case-sensitive"
  if opts.mode == "plain" then
    args[#args + 1] = "--fixed-strings"
  end
  vim.list_extend(args, { "--regexp", query, "--", "." })
  local result = vim.system(args, { cwd = opts.cwd }):wait()
  if result.code > 1 then
    return { items = {}, next_file_offset = 0, regex_fallback_error = result.stderr }
  end
  local all = {}
  for line in result.stdout:gmatch("[^\n]+") do
    local record = vim.json.decode(line)
    if record.type == "match" then
      local d, ranges = record.data, {}
      for _, match in ipairs(d.submatches) do
        ranges[#ranges + 1] = { match.start, match["end"] }
      end
      all[#all + 1] = {
        relative_path = d.path.text or vim.base64.decode(d.path.bytes),
        line_number = d.line_number,
        col = ranges[1][1],
        line_content = d.lines.text:gsub("\n$", ""),
        match_ranges = ranges,
      }
    end
  end
  local items = {}
  local first = opts.file_offset + 1
  for i = first, math.min(#all, first + opts.page_size - 1) do
    items[#items + 1] = all[i]
  end
  return {
    items = items,
    total_files = #all,
    next_file_offset = first + #items <= #all and first + #items - 1 or 0,
  }
end
if mode() == "incompatible" then
  M.content_search = nil
elseif mode() == "missing_file_search" then
  M.file_search = nil
end
return M
