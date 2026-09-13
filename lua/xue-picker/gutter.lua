local api, U = vim.api, require("xue-picker.util")
local M = {}

function M.highlights(prefix)
  prefix = prefix or "XuePicker"
  local H = require("xue-picker.highlights")
  H.default(prefix .. "Pointer", { link = "Special" })
  H.default(prefix .. "Marker", { link = "Special" })
  H.default(prefix .. "Selected", { link = "CursorLine" })
  local gutter = api.nvim_get_hl(0, { name = "FzfLuaFzfGutter", link = false, create = false })
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
  H.default(prefix .. "Gutter", { fg = gutter.bg or normal.bg or "bg" }, {})
end

function M.render(opts, current, marked, prefix, blank)
  prefix = prefix or "XuePicker"
  local pointer, gutter, marker =
    U.clean(opts.pointer or ""), U.clean(opts.gutter or ""), U.clean(opts.marker or "")
  local left_width = math.max(1, vim.fn.strdisplaywidth(pointer), vim.fn.strdisplaywidth(gutter))
  local right_width = math.max(1, vim.fn.strdisplaywidth(marker))
  if blank then
    return string.rep(" ", left_width + right_width), {}, left_width
  end
  local text, spans = "", {}
  local function add(value, width, group)
    local start = #text
    text = text .. value
    if #value > 0 then
      spans[#spans + 1] = { start, #text, prefix .. group, 150 }
    end
    text = text .. string.rep(" ", width - vim.fn.strdisplaywidth(value))
  end
  add(current and pointer or gutter, left_width, current and "Pointer" or "Gutter")
  local pointer_end = #text
  if current and #pointer > 0 then
    spans[#spans + 1] = { 0, #pointer, prefix .. "Strong", 95 }
  end
  add(marked and marker or "", right_width, "Marker")
  return text, spans, pointer_end
end

return M
