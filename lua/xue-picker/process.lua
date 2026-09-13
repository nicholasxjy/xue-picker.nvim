local U = require("xue-picker.util")
local M = {}
-- Keep partial records across arbitrary libuv chunks; parse them in bounded slices.
function M.stream(argv, opts, separator, record, done)
  local queue, head, tail, carry, stderr = {}, 1, 0, "", ""
  local cancelled, exited, draining, proc, finished = false, nil, false, nil, false
  local cancel_drain
  local function drain()
    if draining or cancelled or finished then
      return
    end
    draining = true
    cancel_drain = U.work(function(checkpoint)
      while head <= tail do
        local chunk = carry .. queue[head]
        queue[head] = nil
        head = head + 1
        local from = 1
        while true do
          local pos = chunk:find(separator, from, true)
          if not pos then
            break
          end
          record(chunk:sub(from, pos - 1))
          from = pos + #separator
          checkpoint()
          if cancelled then
            return
          end
        end
        carry = chunk:sub(from)
      end
      if exited and carry ~= "" then
        record(carry)
        carry = ""
      end
    end, function(_, err)
      draining = false
      if cancelled then
        return
      end
      if err then
        cancelled = true
        if proc then
          pcall(proc.kill, proc, 15)
        end
        done(err)
        return
      end
      if head <= tail then
        drain()
      elseif exited then
        finished = true
        done(
          exited.code > (opts.ok_code or 0) and (stderr ~= "" and stderr or "Process exited " .. exited.code)
            or nil,
          exited
        )
      end
    end, opts.slice_ms)
  end
  local ok, result = pcall(vim.system, argv, {
    cwd = opts.cwd,
    text = false,
    stdout = function(err, chunk)
      if cancelled then
        return
      end
      if err then
        stderr = stderr .. tostring(err)
      end
      if chunk then
        tail = tail + 1
        queue[tail] = chunk
        vim.schedule(drain)
      end
    end,
    stderr = function(_, chunk)
      if chunk then
        stderr = (stderr .. chunk):sub(-16384)
      end
    end,
  }, function(result)
    exited = result
    vim.schedule(drain)
  end)
  if ok then
    proc = result
  else
    vim.schedule(function()
      if not cancelled then
        done(tostring(result))
      end
    end)
  end
  return function()
    cancelled = true
    if cancel_drain then
      cancel_drain()
    end
    if proc then
      pcall(proc.kill, proc, 15)
    end
    queue = {}
  end
end
return M
