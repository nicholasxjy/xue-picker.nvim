local U = require("xue-picker.util")
local M = { workers = {}, pending = {}, serial = 0 }
local function stop(worker, reason)
  if worker.closed then
    return
  end
  worker.closed = true
  U.stop(worker.idle)
  M.workers[worker.key] = nil
  if worker.job then
    pcall(vim.fn.jobstop, worker.job)
  end
  local ids = {}
  for id, request in pairs(M.pending) do
    if request.worker == worker then
      ids[#ids + 1] = id
    end
  end
  for _, id in ipairs(ids) do
    M.reply(id, { error = reason or "fff worker exited" })
  end
end
function M.reply(id, result)
  local request = M.pending[id]
  if not request then
    return
  end
  M.pending[id] = nil
  U.stop(request.timer)
  request.callback(result)
end
local function request(worker, method, args, timeout, callback)
  M.serial = M.serial + 1
  local id = M.serial
  local entry = { worker = worker, callback = callback }
  M.pending[id] = entry
  entry.timer = U.later(timeout, function()
    stop(worker, "fff " .. method .. " timed out")
  end)
  local ok = pcall(
    vim.rpcnotify,
    worker.job,
    "nvim_exec_lua",
    "require('xue-picker.grep.worker').request(...)",
    { id, method, args }
  )
  if not ok then
    stop(worker, "Failed to send fff RPC")
  end
  return function()
    local p = M.pending[id]
    if p then
      U.stop(p.timer)
      M.pending[id] = nil
    end
  end
end
function M.detect()
  local files = vim.api.nvim_get_runtime_file("lua/fff.lua", false)
  if #files == 0 then
    files = vim.api.nvim_get_runtime_file("lua/fff/init.lua", false)
  end
  return files[1]
end
function M.shutdown()
  local all = vim.tbl_values(M.workers)
  for _, worker in ipairs(all) do
    stop(worker)
  end
end
local function acquire(opts, callback, files)
  local key = opts.cwd .. "\0" .. vim.o.runtimepath .. "\0" .. (files and "files" or "grep")
  local worker = M.workers[key]
  if worker and worker.ready and not worker.closed then
    U.stop(worker.idle)
    callback(worker)
    return function() end
  end
  if worker then
    stop(worker, "fff initialization superseded")
  end
  worker = { key = key }
  M.workers[key] = worker
  local cache = vim.fn.stdpath("cache")
    .. "/xue-picker/worker/"
    .. vim.uv.os_getpid()
    .. "-"
    .. vim.fn.sha256(opts.cwd):sub(1, 12)
  vim.fn.mkdir(cache, "p")
  worker.job = vim.fn.jobstart(
    { vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "--noplugin" },
    {
      rpc = true,
      cwd = opts.cwd,
      env = {
        NVIM_APPNAME = "xue-picker-worker",
        XDG_CACHE_HOME = cache,
        XDG_DATA_HOME = cache .. "/data",
        XDG_STATE_HOME = cache .. "/state",
      },
      on_exit = function()
        vim.schedule(function()
          stop(worker, "fff worker exited")
        end)
      end,
    }
  )
  if worker.job <= 0 then
    stop(worker)
    callback(nil, "Cannot start fff headless worker")
    return function() end
  end
  vim.rpcnotify(
    worker.job,
    "nvim_exec_lua",
    "local a=...; vim.o.runtimepath=a[1]; package.path=a[2]; package.cpath=a[3]",
    { { vim.o.runtimepath, package.path, package.cpath } }
  )
  if not M.exit_group then
    M.exit_group = vim.api.nvim_create_augroup("XuePickerWorkers", { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", { group = M.exit_group, callback = M.shutdown })
  end
  request(
    worker,
    "init",
    { cwd = opts.cwd, cache = cache, timeout = opts.fff.ready_timeout_ms, files = files or false },
    opts.fff.ready_timeout_ms,
    function(result)
      if result.error then
        stop(worker, result.error)
        callback(nil, result.error)
      else
        worker.ready = true
        callback(worker)
      end
    end
  )
  return function()
    if not worker.ready then
      stop(worker, "fff initialization cancelled")
    end
  end
end
-- File searches share the asynchronous transport, with no grep fallback or query rewriting.
function M.file_search(opts, query, current_file, callback)
  if not M.detect() then
    callback({ error = "smart requires fff with file_search() and its native library in runtimepath" })
    return function() end
  end
  local cancelled, cancel_request, worker = false, nil, nil
  local cancel_init = acquire(opts, function(value, err)
    if cancelled then
      return
    end
    if err then
      callback({ error = err })
      return
    end
    worker = value
    cancel_request = request(
      worker,
      "file_search",
      {
        query = query,
        opts = {
          cwd = opts.cwd,
          mode = opts.mode or "files",
          max_results = opts.max_results,
          page = opts.page or 0,
          current_file = opts.current_file or current_file,
          max_threads = opts.max_threads,
          combo_boost_score_multiplier = opts.combo_boost_score_multiplier,
          min_combo_count = opts.min_combo_count,
          wait_for_index_ms = opts.wait_for_index_ms or 0,
        },
      },
      opts.fff.request_timeout_ms,
      function(result)
        if not cancelled then
          callback(result)
        end
      end
    )
  end, true)
  return function()
    cancelled = true
    if cancel_request then
      cancel_request()
    end
    cancel_init()
    if worker and not worker.closed then
      U.stop(worker.idle)
      worker.idle = U.later(opts.fff.idle_timeout_ms, function()
        stop(worker)
      end)
    end
  end
end
function M.unsupported(opts, query)
  if
    not opts.scan.hidden
    or not opts.scan.ignore
    or opts.scan.follow
    or #opts.scan.globs > 0
    or #opts.globs > 0
    or #opts.ripgrep.args > 0
  then
    return "fff cannot preserve the current scan or filter semantics"
  end
  -- content_search consumes constraint tokens before regex/plain matching.
  -- Route those queries to rg so they retain the literal user-supplied expression.
  if query:find("%s") or query:find("git:", 1, true) or query:find("[!/*?{}]") then
    return "fff content_search constraint syntax cannot preserve the current query semantics"
  end
end
function M.search(opts, query, emit)
  local cancel_normalize
  local cancelled, cancel_request, cancel_init, worker = false, nil, nil, nil
  local reason = M.unsupported(opts, query)
  if reason then
    emit({}, { error = reason, done = true })
    return function() end
  end
  if not M.detect() then
    emit({}, { error = "fff is not installed or not in runtimepath", done = true })
    return function() end
  end
  local count, offset, seen = 0, 0, {}
  local function page()
    if cancelled or worker.closed then
      return
    end
    cancel_request = request(
      worker,
      "search",
      {
        query = query,
        opts = {
          cwd = opts.cwd,
          mode = opts.mode,
          smart_case = opts.smartcase,
          trim_whitespace = false,
          max_file_size = opts.max_file_size,
          max_matches_per_file = opts.max_results,
          page_size = opts.fff.page_size,
          file_offset = offset,
          time_budget_ms = opts.fff.time_budget_ms,
          enforce_time_budget = true,
          wait_for_index_ms = 0,
        },
      },
      opts.fff.request_timeout_ms,
      function(result)
        if cancelled then
          return
        end
        if result.error then
          emit({}, { error = result.error, kind = result.kind, done = true })
          return
        end
        cancel_normalize = U.work(function(checkpoint)
          local items = {}
          for _, match in ipairs(result.items) do
            if count >= opts.max_results then
              break
            end
            local path = U.path(assert(match.relative_path), opts.cwd)
            local row = assert(tonumber(match.line_number), "fff is missing line_number")
            local col = assert(tonumber(match.col), "fff is missing col")
            local ranges = {}
            for _, range in ipairs(match.match_ranges or {}) do
              assert(
                type(range[1]) == "number" and type(range[2]) == "number",
                "Incompatible fff match_ranges"
              )
              ranges[#ranges + 1] = { range[1], range[2] }
            end
            if #ranges > 0 then
              col = ranges[1][1]
            end
            local id = path .. "\0" .. row .. ":" .. col
            if not seen[id] and count < opts.max_results then
              seen[id] = true
              count = count + 1
              items[#items + 1] = {
                id = id,
                path = path,
                file = path,
                lnum = row,
                col = col,
                text = assert(match.line_content),
                ranges = ranges,
                _prepared_cwd = opts.cwd,
              }
            end
            checkpoint()
          end
          return items
        end, function(items, err)
          if cancelled then
            return
          end
          if err then
            emit({}, { error = tostring(err), done = true })
            return
          end
          local next_offset = result.next_file_offset
          if next_offset ~= 0 and next_offset <= offset then
            emit({}, { error = "fff pagination offset did not advance", done = true })
            return
          end
          local done = next_offset == 0 or count >= opts.max_results
          emit(items, { done = done, truncated = count >= opts.max_results })
          if not done then
            offset = next_offset
            vim.schedule(page)
          end
        end, opts.performance.slice_ms)
      end
    )
  end
  cancel_init = acquire(opts, function(value, err)
    if cancelled then
      return
    end
    if err then
      emit({}, { error = err, done = true })
      return
    end
    worker = value
    page()
  end)
  return function()
    cancelled = true
    if cancel_normalize then
      cancel_normalize()
    end
    if cancel_request then
      cancel_request()
    end
    if cancel_init then
      cancel_init()
    end
    if worker and not worker.closed then
      U.stop(worker.idle)
      worker.idle = U.later(opts.fff.idle_timeout_ms, function()
        stop(worker)
      end)
    end
  end
end
return M
