local U = require("xue-picker.util")
local M = {}
function M.cancel(session)
  U.stop(session.preview_timer)
  session.preview_generation = (session.preview_generation or 0) + 1
end
function M.update(s)
  M.cancel(s)
  if not s.preview_enabled or not s.ui.wins.preview then
    return
  end
  local item = s.results[s.index]
  if not item then
    s.ui:preview({ "No preview" })
    return
  end
  local gen, opts = s.preview_generation, s.opts.preview
  local location = not s.opts.live and s.ranker and s.ranker:location(s.query)
  local target = location and location[1] or item.lnum or 1
  local function valid()
    return not s.closed and gen == s.preview_generation
  end
  local function show(lines)
    if not valid() then
      return
    end
    local first = math.max(1, target - math.floor(opts.max_lines / 2))
    if #lines <= opts.max_lines then
      first = 1
    end
    local out = {}
    for i = first, math.min(#lines, first + opts.max_lines - 1) do
      out[#out + 1] = ("%5d  %s"):format(i, U.clean(lines[i]))
    end
    s.ui:preview(#out > 0 and out or { "Empty file" }, target - first + 1)
  end
  s.preview_timer = U.later(opts.debounce_ms, function()
    if not valid() then
      return
    end
    if s.opts.preview_item then
      local ok, info = pcall(s.opts.preview_item, item.value or item)
      if ok then
        s.ui:external_preview(info)
      else
        s.ui:preview({ tostring(info) })
      end
      return
    end
    local buf = item.bufnr or item.path and vim.fn.bufnr(item.path)
    if buf and buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
      local count = vim.api.nvim_buf_line_count(buf)
      local first = math.max(0, target - 1 - math.floor(opts.max_lines / 2))
      if vim.api.nvim_buf_get_offset(buf, count) > opts.max_bytes then
        s.ui:preview({ "File exceeds the preview size limit" })
        return
      end
      local lines = vim.api.nvim_buf_get_lines(buf, first, math.min(count, first + opts.max_lines), false)
      local formatted = {}
      for i, line in ipairs(lines) do
        formatted[i] = ("%5d  %s"):format(first + i, U.clean(line))
      end
      s.ui:preview(formatted, target - first)
      return
    end
    if not item.path then
      s.ui:preview({ item.text or "No preview" })
      return
    end
    vim.uv.fs_stat(
      item.path,
      vim.schedule_wrap(function(err, stat)
        if not valid() then
          return
        end
        if err or not stat then
          s.ui:preview({ "Cannot read file: " .. tostring(err) })
          return
        end
        if stat.type ~= "file" then
          s.ui:preview({ "Not a regular file" })
          return
        end
        if stat.size > opts.max_bytes then
          s.ui:preview({ "File exceeds the preview size limit" })
          return
        end
        U.read(item.path, opts.max_bytes + 1, function(data, read_err)
          if not valid() then
            return
          end
          if read_err then
            s.ui:preview({ tostring(read_err) })
          elseif #data > opts.max_bytes then
            s.ui:preview({ "File exceeds the preview size limit" })
          elseif data:find("\0", 1, true) then
            s.ui:preview({ "Binary file; preview unavailable" })
          else
            show(vim.split(data, "\n", { plain = true }))
          end
        end)
      end)
    )
  end)
end
return M
