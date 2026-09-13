local U = require("xue-picker.util")
local M = { cache = {}, tick = 0 }
local function argv(opts)
  local scan = opts.scan
  local args = { scan.cmd, "--files", "--null" }
  if scan.hidden then
    args[#args + 1] = "--hidden"
  end
  if not scan.ignore then
    args[#args + 1] = "--no-ignore"
  end
  if scan.follow then
    args[#args + 1] = "--follow"
  end
  vim.list_extend(args, { "--glob", "!.git", "--glob", "!.git/**" })
  for _, glob in ipairs(scan.globs) do
    vim.list_extend(args, { "--glob", glob })
  end
  vim.list_extend(args, scan.args)
  args[#args + 1] = "."
  return args
end
function M.key(opts)
  return opts.cwd .. "\0" .. table.concat(argv(opts), "\0")
end
function M.put(key, items, opts)
  M.tick = M.tick + 1
  M.cache[key] = { items = items, used = M.tick }
  while true do
    local count, entries, oldest, age = 0, 0, nil, math.huge
    for k, value in pairs(M.cache) do
      count, entries = count + 1, entries + #value.items
      if value.used < age then
        oldest, age = k, value.used
      end
    end
    if count <= opts.performance.cache_dirs and entries <= opts.performance.cache_entries then
      break
    end
    M.cache[oldest] = nil
  end
end
function M.scan(opts, emit)
  local key, items = M.key(opts), {}
  local cached = M.cache[key]
  if cached then
    M.tick = M.tick + 1
    cached.used = M.tick
    emit(cached.items, { loading = true, cached = true, replace = true, seed = cached.seed, cache_key = key })
  end
  if vim.fn.executable(opts.scan.cmd) ~= 1 then
    emit({}, { error = "文件扫描需要 ripgrep (rg): " .. opts.scan.cmd, replace = true, done = true })
    return function() end
  end
  return require("xue-picker.process").stream(
    argv(opts),
    { cwd = opts.cwd, slice_ms = opts.performance.slice_ms, ok_code = 1 },
    "\0",
    function(path)
      items[#items + 1] = U.file(path, opts.cwd)
    end,
    function(err)
      if not err then
        M.put(key, items, opts)
      end
      emit(items, { error = err, done = true, replace = true, cache_key = key })
    end
  )
end
function M.git(opts, callback)
  local root
  local stop = require("xue-picker.process").stream(
    { "git", "rev-parse", "--show-toplevel" },
    { cwd = opts.cwd },
    "\n",
    function(line)
      root = line
    end,
    function(err)
      if err or not root then
        callback({})
        return
      end
      local statuses, rename = {}, false
      stop = require("xue-picker.process").stream(
        { "git", "status", "--porcelain=v1", "-z", "--untracked-files=normal" },
        { cwd = opts.cwd },
        "\0",
        function(line)
          if rename then
            rename = false
            return
          end
          local status = line:sub(1, 2)
          statuses[U.path(line:sub(4), root)] = status
          rename = status:find("[RC]") ~= nil
        end,
        function()
          callback(statuses)
        end
      )
    end
  )
  return function()
    if stop then
      stop()
    end
  end
end
return M
