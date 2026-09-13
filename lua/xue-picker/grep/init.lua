local M = { last_fallback = nil }
function M.new(opts)
  assert(vim.tbl_contains({ "auto", "fff", "ripgrep" }, opts.backend), "backend 必须是 auto/fff/ripgrep")
  assert(opts.mode == "regex" or opts.mode == "plain", "mode 必须是 regex/plain")
  assert(opts.max_results > 0, "max_results 必须大于零")
  local backend = opts.backend == "ripgrep" and "ripgrep" or "fff"
  local serial, cancel = 0, nil
  return function(query, emit)
    serial = serial + 1
    local gen = serial
    if cancel then
      cancel()
      cancel = nil
    end
    emit({}, { replace = true, loading = query ~= "", done = query == "", backend = backend })
    if query == "" then
      return function() end
    end
    local function run()
      local chosen = backend
      local function output(items, state)
        if serial ~= gen then
          return
        end
        if
          state.error
          and chosen == "fff"
          and state.kind ~= "query"
          and (opts.backend == "auto" or opts.fallback)
        then
          M.last_fallback = state.error
          backend = "ripgrep"
          -- Delay until the failing search has returned its cancellation handle.
          vim.schedule(function()
            if serial ~= gen then
              return
            end
            if cancel then
              cancel()
              cancel = nil
            end
            emit({}, { replace = true, loading = true, backend = backend, fallback = M.last_fallback })
            run()
          end)
          return
        end
        state.backend = chosen
        emit(items, state)
      end
      cancel = require("xue-picker.grep." .. chosen).search(opts, query, output)
    end
    run()
    return function()
      if serial == gen then
        serial = serial + 1
        if cancel then
          cancel()
          cancel = nil
        end
      end
    end
  end
end
return M
