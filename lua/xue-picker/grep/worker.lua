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
        error("fff Lua 接口不可用: " .. tostring(module))
      end
      assert(type(module.content_search) == "function", "fff API 不兼容: 缺少 content_search()")
      local native_ok, native = pcall(require, "fff.fuzzy")
      assert(native_ok and type(native) == "table", "fff 原生库不可用: " .. tostring(native))
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
      -- A zero-limit file search waits for readiness without scanning contents.
      assert(type(fff.file_search) == "function", "fff API 不兼容: 缺少 file_search()")
      fff.file_search("", { cwd = args.cwd, max_results = 1, wait_for_index_ms = args.timeout })
      return { ready = true }
    end
    assert(fff, "fff worker 未初始化")
    local result = fff.content_search(args.query, args.opts)
    assert(
      type(result) == "table" and type(result.items) == "table" and type(result.next_file_offset) == "number",
      "fff content_search 返回值不兼容"
    )
    if result.regex_fallback_error and result.regex_fallback_error ~= vim.NIL then
      return { error = "无效 regex: " .. result.regex_fallback_error, kind = "query" }
    end
    return result
  end)
  vim.rpcnotify(1, "nvim_exec_lua", "require('xue-picker.grep.fff').reply(...)", { id, result })
end
return M
