local M = {}
local uv = vim.uv
local windows = vim.fn.has("win32") == 1
function M.path(path, cwd)
  if not path or path == "" then
    return nil
  end
  if not path:match("^/") and not (windows and (path:match("^\\") or path:match("^%a:[/\\]"))) then
    path = (cwd or vim.fn.getcwd()) .. "/" .. path
  end
  path = vim.fs.normalize(path, { expand_env = false }):gsub("/$", "")
  if windows then
    path = path:gsub("\\", "/")
  end
  if path == "" then
    path = "/"
  end
  return windows and path:lower() or path
end
function M.cwd(path)
  path = path or vim.fn.getcwd()
  if path == "~" or path:sub(1, 2) == "~/" then
    path = vim.uv.os_homedir() .. path:sub(2)
  end
  path = M.path(path)
  return vim.uv.fs_realpath(path) or path
end
function M.inside(path, cwd)
  return path == cwd or path:sub(1, #(cwd:gsub("/$", "") .. "/")) == cwd:gsub("/$", "") .. "/"
end
function M.relative(path, cwd)
  return M.inside(path, cwd) and path:sub(#cwd:gsub("/$", "") + 2) or path
end
function M.clean(text)
  return tostring(text or ""):gsub("[%z\1-\31\127]", function(c)
    return ({ ["\n"] = "↵", ["\r"] = "␍", ["\t"] = "⇥" })[c] or "?"
  end)
end
function M.stop(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end
function M.later(ms, fn)
  local timer = uv.new_timer()
  timer:start(
    ms,
    0,
    vim.schedule_wrap(function()
      M.stop(timer)
      fn()
    end)
  )
  return timer
end
-- A cancellation-aware coroutine. All scheduled work resumes on the main loop.
function M.work(fn, done, budget)
  local cancelled, started = false, 0
  local timer
  local co = coroutine.create(function()
    return fn(function()
      if (uv.hrtime() - started) / 1e6 >= (budget or 4) then
        coroutine.yield()
      end
    end)
  end)
  local function step()
    if cancelled then
      return
    end
    started = uv.hrtime()
    local ok, result = coroutine.resume(co)
    if M.on_slice then
      M.on_slice((uv.hrtime() - started) / 1e6)
    end
    if not ok then
      done(nil, debug.traceback(co, tostring(result)))
    elseif coroutine.status(co) == "dead" then
      done(result)
    else
      timer = M.later(1, step)
    end
  end
  vim.schedule(step)
  return function()
    cancelled = true
    M.stop(timer)
  end
end
function M.file(path, cwd)
  local absolute = M.path(path, cwd)
  return {
    id = absolute,
    path = absolute,
    file = absolute,
    text = M.relative(absolute, cwd),
    _prepared_cwd = cwd,
  }
end
function M.sort(values, less, checkpoint)
  checkpoint = checkpoint or function() end
  if #values < 512 then
    table.sort(values, less)
    return values
  end
  local source, target, width = values, {}, 1
  while width < #values do
    for start = 1, #values, width * 2 do
      local a, b = start, start + width
      local ae, be = math.min(start + width - 1, #values), math.min(start + width * 2 - 1, #values)
      for i = start, be do
        if b > be or a <= ae and not less(source[b], source[a]) then
          target[i] = source[a]
          a = a + 1
        else
          target[i] = source[b]
          b = b + 1
        end
        if i % 128 == 0 then
          checkpoint()
        end
      end
    end
    source, target, width = target, source, width * 2
  end
  if source ~= values then
    for i, value in ipairs(source) do
      values[i] = value
      if i % 128 == 0 then
        checkpoint()
      end
    end
  end
  return values
end
function M.read(path, limit, callback)
  uv.fs_open(path, "r", 438, function(err, fd)
    if err then
      vim.schedule(function()
        callback(nil, err)
      end)
      return
    end
    uv.fs_read(fd, limit, 0, function(read_err, data)
      uv.fs_close(fd)
      vim.schedule(function()
        callback(data, read_err)
      end)
    end)
  end)
end
return M
