-- Deterministic optional-backend double. Runs through the real worker/RPC path.
local M = {}
local function mode()
  return vim.env.XUE_TEST_FFF_MODE
end
function M.setup() end
function M.file_search(_, opts)
  -- Programmatic initialization does not initialize fff's picker UI state.
  if mode() == "uninitialized_picker_ui" and opts.wait_for_index_ms > 0 then
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
end
return M
