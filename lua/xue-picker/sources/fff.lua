local U = require("xue-picker.util")
local M = {}
function M.search(opts, ctx, emit)
  local cancel_normalize
  local path = vim.api.nvim_buf_get_name(ctx.session.origin.buf)
  local current_file = path ~= "" and vim.uv.fs_realpath(path) or nil
  current_file = current_file
      and U.inside(current_file, opts.cwd)
      and vim.fn.filereadable(current_file) == 1
      and U.relative(current_file, opts.cwd)
    or nil
  local cancel_search = require("xue-picker.grep.fff").file_search(
    opts,
    ctx.query,
    current_file,
    function(result)
      if result.error then
        emit({}, { error = result.error, backend = "fff", replace = true, done = true })
        return
      end
      cancel_normalize = U.work(function(checkpoint)
        local items = {}
        local location = type(result.location) == "table" and result.location or nil
        location = location and (location.start or location)
        for i, match in ipairs(result.items) do
          local kind = match.type or (opts.mode == "directories" and "directory" or "file")
          local path = assert(match.relative_path)
          -- fff represents the indexed root directory with an empty relative path.
          local item = U.file(kind == "directory" and path == "" and "." or path, opts.cwd)
          item.type = kind
          if item.text == "" then
            item.text = "."
          end
          local score = result.scores and result.scores[i]
          item.fff_score, item.git_status = score, match.git_status
          item.score = type(score) == "table" and score.total or nil
          item.ranges = match.match_ranges
          if location and item.type ~= "directory" then
            item.lnum, item.col = location.line, math.max(0, (location.col or 1) - 1)
          end
          items[#items + 1] = item
          checkpoint()
        end
        return items
      end, function(items, err)
        emit(items or {}, {
          error = err,
          backend = "fff",
          replace = true,
          done = true,
          truncated = result.total_matched > #result.items,
        })
      end, opts.performance.slice_ms)
    end
  )
  return function()
    cancel_search()
    if cancel_normalize then
      cancel_normalize()
    end
  end
end
return M
