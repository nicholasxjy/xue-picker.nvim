-- Runs only in the isolated headless Neovim. No picker UI is invoked here.
local M = {}
local fff
local function guarded(fn)
  local original, errors = vim.notify, {}
  vim.notify = function(message, level)
    if (level or vim.log.levels.INFO) >= vim.log.levels.ERROR then
      errors[#errors + 1] = tostring(message)
    end
  end
  local ok, result = xpcall(fn, debug.traceback)
  vim.notify = original
  if not ok then
    return { error = tostring(result) }
  end
  if #errors > 0 then
    return { error = table.concat(errors, "\n") }
  end
  return result
end
function M.request(id, method, args)
  local result = guarded(function()
    if method == "init" then
      local ok, module = pcall(require, "fff")
      if not ok then
        error("fff Lua API is unavailable: " .. tostring(module))
      end
      if not args.files then
        assert(type(module.content_search) == "function", "Incompatible fff API: missing content_search()")
      end
      local native_ok, native = pcall(require, "fff.fuzzy")
      assert(native_ok and type(native) == "table", "fff native library is unavailable: " .. tostring(native))
      fff = module
      fff.setup({
        base_path = args.cwd,
        lazy_sync = true,
        follow_symlinks = false,
        frecency = { enabled = false, db_path = args.cache .. "/frecency" },
        history = { enabled = false, db_path = args.cache .. "/history" },
        logging = { enabled = false, log_file = args.cache .. "/fff.log" },
        grep = { enable_filename_constraint = false },
      })
      -- Start indexing without waiting through fff's uninitialized picker UI state.
      assert(type(fff.file_search) == "function", "Incompatible fff API: missing file_search()")
      assert(
        type(native.wait_for_initial_scan) == "function",
        "Incompatible fff native library: missing wait_for_initial_scan()"
      )
      fff.file_search("", { cwd = args.cwd, max_results = 1, wait_for_index_ms = 0 })
      assert(native.wait_for_initial_scan(args.timeout), "fff index scan timed out")
      return { ready = true }
    end
    assert(fff, "fff worker is not initialized")
    if method == "file_search" then
      local result = fff.file_search(args.query, args.opts)
      assert(
        type(result) == "table" and type(result.items) == "table" and type(result.total_matched) == "number",
        "Incompatible fff file_search return value"
      )
      return result
    end
    local result = fff.content_search(args.query, args.opts)
    assert(
      type(result) == "table" and type(result.items) == "table" and type(result.next_file_offset) == "number",
      "Incompatible fff content_search return value"
    )
    if result.regex_fallback_error and result.regex_fallback_error ~= vim.NIL then
      return { error = "Invalid regex: " .. result.regex_fallback_error, kind = "query" }
    end
    return result
  end)
  vim.rpcnotify(1, "nvim_exec_lua", "require('xue-picker.grep.fff').reply(...)", { id, result })
end
return M
