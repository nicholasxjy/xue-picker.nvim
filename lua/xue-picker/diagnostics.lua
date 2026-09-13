local U = require("xue-picker.util")
local M = {}

function M.sort(values, opts)
  if opts.sort == false then
    return values
  end
  if type(opts.sort) == "function" then
    local result = opts.sort(values, opts)
    assert(type(result) == "table", "diagnostics.sort must return a diagnostic array")
    return result
  end
  local reverse = opts.sort == "reverse" or opts.sort == 2 or opts.sort == "2"
  assert(
    reverse or opts.sort == true or opts.sort == 1 or opts.sort == "1",
    "diagnostics.sort must be true, false, 1, 2, 'reverse', or a function"
  )
  local order = {}
  for i, value in ipairs(values) do
    order[value] = i
  end
  table.sort(values, function(a, b)
    if a.severity ~= b.severity then
      if reverse then
        return a.severity > b.severity
      end
      return a.severity < b.severity
    end
    for _, field in ipairs({ "bufnr", "lnum", "col" }) do
      if a[field] ~= b[field] then
        return a[field] < b[field]
      end
    end
    return order[a] < order[b]
  end)
  return values
end

local levels = { "Error", "Warn", "Info", "Hint" }
local function sign(item, opts)
  local severity = item.severity or vim.diagnostic.severity.ERROR
  local level = levels[severity] or "Error"
  local configured = type(opts.diag_icons) == "table" and { text = opts.diag_icons }
    or vim.diagnostic.config().signs
  local text = level:sub(1, 1)
  if opts.diag_icons and type(configured) == "table" and configured.text and configured.text[severity] then
    text = vim.trim(configured.text[severity])
  end
  local override = (opts.signs or {})[level] or {}
  return override.text or text, override.texthl or "XuePickerDiagnostic" .. level
end

-- Each row carries its own byte spans, so wrapping never splits UTF-8 highlights.
function M.format(item, session, width, file_icon, file_icon_group)
  local opts = session.opts
  local G = require("xue-picker.gutter")
  local current = session.results[session.index] == item
  local prefix, spans = G.render(opts, current, session.selected[item.id])
  local gutter_width = vim.fn.strdisplaywidth(prefix)
  local rows = { { text = prefix, spans = spans } }
  local row, columns = rows[1], vim.fn.strdisplaywidth(prefix)
  local function newline()
    local gutter, marks = G.render(opts, current, false)
    row = { text = gutter, spans = marks }
    rows[#rows + 1], columns = row, gutter_width
  end
  local function put(value, group, priority)
    for char in U.clean(value):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      local size = vim.fn.strdisplaywidth(char)
      if columns + size > width and columns > gutter_width then
        newline()
      end
      local start = #row.text
      row.text, columns = row.text .. char, columns + size
      if group then
        priority = priority or 150
        local last = row.spans[#row.spans]
        if last and last[2] == start and last[3] == group and last[4] == priority then
          last[2] = #row.text
        else
          row.spans[#row.spans + 1] = { start, #row.text, group, priority }
        end
      end
    end
  end
  local symbol, severity_group = sign(item, opts)
  put(symbol, opts.color_icons and severity_group or nil)
  put((opts.icon_padding or "") .. " ")
  if opts.diag_source and item.source and item.source ~= "" then
    put("[" .. item.source .. "]", opts.color_headings and severity_group or nil)
    put(" ")
  end
  if file_icon and file_icon ~= "" then
    put(file_icon, file_icon_group or "XuePickerIcon")
  end
  local path = item.path and U.relative(item.path, opts.cwd) or "[No Name]"
  if type(opts.path_format) == "function" and item.path then
    path = opts.path_format(item, opts.cwd)
  end
  if opts.path_format == "filename_first" then
    local directory, filename = path:match("^(.*)[/\\]([^/\\]+)$")
    put(filename or path, "XuePickerFilename", 100)
    if directory then
      put(" ")
      put(directory, "XuePickerDirectory")
    end
  else
    put(path, opts.color_headings and severity_group or nil)
  end
  put(":")
  put(tostring(item.lnum or 1), "XuePickerLineNr")
  put(":")
  put(tostring((item.col or 0) + 1), "XuePickerColNr")
  put(":")
  if opts.multiline then
    newline()
    put("    ")
  end
  put(" ")
  local message = item.text or ""
  local first = message:find("%S") or #message + 1
  local last = message:match(".*%S()") or first
  if not opts.multiline then
    last = math.min(last, message:find("\n", 1, true) or last)
    while last > first and message:sub(last - 1, last - 1):match("%s") do
      last = last - 1
    end
  end
  local matches = session.ranker and session.ranker:byte_positions(session.query, item) or {}
  for offset, char in message:sub(first, last - 1):gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do
    if char == "\n" then
      newline()
    else
      local matched = false
      for byte = first + offset - 2, first + offset + #char - 3 do
        matched = matched or matches[byte]
      end
      put(char, matched and "XuePickerMatch" or nil)
    end
  end
  if opts.diag_code and item.code ~= nil then
    put(" [" .. tostring(item.code) .. "]", "XuePickerDiagnosticCode")
  end
  if opts.multiline then
    for _ = 1, math.max(0, (tonumber(opts.multiline) or 1) - 1) do
      rows[#rows + 1] = { text = "", spans = {}, gap = true }
    end
  end
  local first_row = table.remove(rows, 1)
  return first_row.text, first_row.spans, nil, rows
end

return M
