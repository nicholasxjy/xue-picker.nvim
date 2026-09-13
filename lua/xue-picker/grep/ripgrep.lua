local U = require("xue-picker.util")
local M = {}
local function decode(value)
  if value.text then
    return value.text
  end
  return value.bytes and vim.base64.decode(value.bytes) or ""
end
function M.search(opts, query, emit)
  if vim.fn.executable(opts.ripgrep.cmd) ~= 1 then
    emit({}, { error = "Content search requires fff or ripgrep (rg): " .. opts.ripgrep.cmd, done = true })
    return function() end
  end
  local args = {
    opts.ripgrep.cmd,
    "--json",
    "--line-number",
    "--column",
    "--color=never",
    "--no-heading",
    "--max-filesize",
    tostring(opts.max_file_size),
    "--glob",
    "!.git",
    "--glob",
    "!.git/**",
  }
  if opts.mode == "plain" then
    args[#args + 1] = "--fixed-strings"
  end
  args[#args + 1] = opts.smartcase and "--smart-case" or "--case-sensitive"
  if opts.scan.hidden then
    args[#args + 1] = "--hidden"
  end
  if not opts.scan.ignore then
    args[#args + 1] = "--no-ignore"
  end
  if opts.scan.follow then
    args[#args + 1] = "--follow"
  end
  for _, glob in ipairs(opts.scan.globs) do
    vim.list_extend(args, { "--glob", glob })
  end
  for _, glob in ipairs(opts.globs) do
    vim.list_extend(args, { "--glob", glob })
  end
  vim.list_extend(args, opts.ripgrep.args)
  vim.list_extend(args, { "--regexp", query, "--", "." })
  local batch, count, truncated, timer, cancel = {}, 0, false, nil, nil
  local function flush(state)
    U.stop(timer)
    timer = nil
    local items = batch
    batch = {}
    emit(items, state or {})
  end
  cancel = require("xue-picker.process").stream(
    args,
    { cwd = opts.cwd, ok_code = 1, slice_ms = opts.performance.slice_ms },
    "\n",
    function(line)
      if truncated or line == "" then
        return
      end
      local event = vim.json.decode(line)
      if event.type ~= "match" then
        return
      end
      local d = event.data
      local path, raw = U.path(decode(d.path), opts.cwd), decode(d.lines):gsub("\n$", ""):gsub("\r$", "")
      local ranges = {}
      for _, match in ipairs(d.submatches) do
        ranges[#ranges + 1] = { match.start, match["end"] }
      end
      count = count + 1
      local col = ranges[1] and ranges[1][1] or 0
      batch[#batch + 1] = {
        id = path .. "\0" .. d.line_number .. ":" .. col,
        path = path,
        file = path,
        lnum = d.line_number,
        col = col,
        text = raw,
        ranges = ranges,
        _prepared_cwd = opts.cwd,
      }
      if count >= opts.max_results then
        truncated = true
        if cancel then
          cancel()
        end
        flush({ done = true, truncated = true })
      elseif not timer then
        timer = U.later(opts.performance.render_ms, flush)
      end
    end,
    function(err)
      if not truncated then
        flush({ error = err, done = true })
      end
    end
  )
  return function()
    U.stop(timer)
    if cancel then
      cancel()
    end
  end
end
return M
