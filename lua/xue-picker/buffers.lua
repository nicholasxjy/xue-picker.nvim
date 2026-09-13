local api, U = vim.api, require("xue-picker.util")
local M = {}
local space = " " -- fzf-lua's U+2002 field separator.

function M.highlights()
  local light = vim.o.background == "light"
  local defaults = {
    XuePickerBufferNumber = { fg = light and "AquaMarine3" or "BlanchedAlmond" },
    XuePickerBufferCurrent = { fg = light and "Brown4" or "Brown1" },
    XuePickerBufferAlternate = { fg = light and "CadetBlue4" or "CadetBlue1" },
    XuePickerBufferLineNr = { fg = light and "MediumSpringGreen" or "LightGreen" },
    XuePickerBufferHeader = { link = "Normal" },
    XuePickerBufferSelected = { link = "CursorLine" },
    XuePickerBufferMatch = { link = "Special" },
    XuePickerBufferPointer = { link = "Special" },
    XuePickerBufferMarker = { link = "Special" },
  }
  for name, fallback in pairs(defaults) do
    require("xue-picker.highlights").default(name, fallback)
  end
  local gutter = api.nvim_get_hl(0, { name = "FzfLuaFzfGutter", link = false, create = false })
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
  require("xue-picker.highlights").default(
    "XuePickerBufferGutter",
    { fg = gutter.bg or normal.bg or "bg" },
    {}
  )
end

function M.source(ctx, emit, opts)
  local s, items, current = ctx.session, {}, nil
  local scratch = {}
  for _, buf in pairs(s.ui.bufs) do
    scratch[buf] = true
  end
  for _, info in ipairs(vim.fn.getbufinfo()) do
    local buf, bo = info.bufnr, vim.bo[info.bufnr]
    if
      not scratch[buf]
      and bo.filetype ~= "qf"
      and (opts.show_unlisted or bo.buflisted or buf == s.origin.buf)
      and (opts.show_unloaded or info.loaded == 1)
      and not (opts.ignore_current_buffer and buf == s.origin.buf)
    then
      local name = info.name
      if bo.buftype == "terminal" and vim.b[buf].term_title then
        name = "term://" .. vim.b[buf].term_title:gsub("^term://", "")
      end
      local special = name == "" or name:match("^%[.*%]$") or name:match("^%a[%w+.-]*://")
      local item = special and { text = name ~= "" and name or "[No Name]" } or U.file(name, opts.cwd)
      item.id, item.bufnr, item.info = "buffer:" .. buf, buf, info
      item.icon_path = bo.buftype == "terminal" and "term" or nil
      if opts.filename_only and item.path then
        item.text = vim.fs.basename(item.path)
      elseif opts.filename_only and item.icon_path then
        item.text = vim.fs.basename(name)
      end
      item.flag = buf == s.origin.buf and "%" or buf == s.origin.alternate and "#" or " "
      item.status = item.flag
        .. (info.hidden == 1 and "h" or info.loaded == 1 and "a" or " ")
        .. (bo.readonly and "=" or " ")
        .. (bo.modified and "+" or " ")
      -- Display/preview the saved line without forcing the accept action to move the cursor.
      item.buffer_lnum = (item.path or bo.buftype == "terminal") and info.lnum or nil
      if buf == s.origin.buf and opts.sort_lastused then
        if not opts.filter.cwd or not item.path or U.inside(item.path, opts.cwd) then
          if not opts.filter.fn or opts.filter.fn(item, s) then
            current = item
          end
        end
      else
        items[#items + 1] = item
      end
    end
  end
  if opts.sort_lastused then
    table.sort(items, function(a, b)
      if (a.flag == "#") ~= (b.flag == "#") then
        return a.flag == "#"
      end
      local left, right = a.info.lastused or 0, b.info.lastused or 0
      return left > right or left == right and a.bufnr < b.bufnr
    end)
  end
  s.buffer_header = current
  if current then
    s.selected[current.id] = nil
  end
  emit(items, { replace = true, done = true })
end

function M.number_width(s)
  local maximum = s.buffer_header and s.buffer_header.bufnr or 0
  for _, item in ipairs(s.items) do
    maximum = math.max(maximum, item.bufnr or 0)
  end
  for _, item in ipairs(s.results) do
    maximum = math.max(maximum, item.bufnr or 0)
  end
  return #tostring(maximum)
end

function M.format(item, s, width, number_width, selected, icon, icon_group)
  local opts, text, spans, map = s.opts, "", {}, {}
  local function add(value, group, priority, logical)
    value = tostring(value or "")
    local start = #text
    if logical then
      for first, char in value:gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do
        local clean = U.clean(char)
        for b = first, first + #char - 1 do
          map[logical + b - 1] = { #text, #text + #clean }
        end
        text = text .. clean
      end
    else
      text = text .. U.clean(value)
    end
    if group and #text > start then
      spans[#spans + 1] = { start, #text, group, priority or 150 }
    end
  end
  local header = item == s.buffer_header
  add(
    header and " " or selected and opts.pointer or opts.gutter,
    not header and (selected and "XuePickerBufferPointer" or "XuePickerBufferGutter") or nil
  )
  local pointer_end = #text
  local marked = not header and s.selected[item.id]
  add(marked and opts.marker or " ", marked and "XuePickerBufferMarker" or nil)
  local gutter_end = #text
  add("[")
  add(item.bufnr, "XuePickerBufferNumber")
  add("]" .. string.rep(" ", math.max(1, number_width - #tostring(item.bufnr) + 1)) .. space)
  local status = item.status or "    "
  local flag = status:sub(1, 1)
  add(
    flag == " " and space or flag,
    flag == "%" and "XuePickerBufferCurrent" or flag == "#" and "XuePickerBufferAlternate" or nil
  )
  add(status:sub(2) .. space .. space)
  if (item.path or item.icon_path) and not opts.filename_only and icon and icon ~= "" then
    add(icon:gsub("%s+$", ""), icon_group or "XuePickerIcon")
    add(space)
  end
  local path = item.text
  if item.path then
    path = U.relative(item.path, opts.cwd)
    local home = vim.uv.os_homedir()
    if U.inside(path, home) then
      path = "~" .. path:sub(#home + 1)
    end
  end
  local directory, filename = path:match("^(.*[/\\])([^/\\]+)$")
  local shift = #item.text - #path
  local function add_path(value, start, group, priority)
    if start == 0 and shift > 0 and value:sub(1, 1) == "~" then
      add("~", group, priority)
      add(value:sub(2), group, priority, shift + 1)
    else
      add(value, group, priority, shift + start)
    end
  end
  if item.path and type(opts.path_format) == "function" and not opts.filename_only then
    add(opts.path_format(item, opts.cwd), "XuePickerFilename", 100)
  elseif item.path and (opts.filename_only or opts.path_format == "filename_first") then
    add_path(
      filename or path,
      #path - #(filename or path),
      opts.filename_only and nil or "XuePickerFilename",
      100
    )
    if directory and not opts.filename_only then
      add(" ")
      add_path(directory:sub(1, -2), 0, "XuePickerDirectory", 100)
    end
  else
    add_path(path, 0)
  end
  if item.buffer_lnum and not opts.filename_only then
    add(":")
    add(item.buffer_lnum, "XuePickerBufferLineNr")
  end
  if header then
    spans[#spans + 1] = { gutter_end, #text, "XuePickerBufferHeader", 80 }
  end
  local last_match
  if not header and s.ranker then
    for b in pairs(s.ranker:byte_positions(s.query, item)) do
      if map[b] then
        spans[#spans + 1] = { map[b][1], map[b][2], "XuePickerBufferMatch", 200 }
        last_match = math.max(last_match or 0, map[b][2])
      end
    end
  end
  text, spans = require("xue-picker.text").scroll(
    text,
    spans,
    width,
    gutter_end,
    last_match,
    header and "XuePickerBufferHeader" or selected and "XuePickerBufferSelected" or "XuePickerNormal"
  )
  for i = 1, #spans do
    local span = spans[i]
    if span[3] == "XuePickerBufferMatch" then
      spans[#spans + 1] = { span[1], span[2], "XuePickerBufferStrong", 190 }
    end
  end
  if selected and not header then
    text = text .. string.rep(" ", math.max(0, width - 1 - vim.fn.strdisplaywidth(text)))
    spans[#spans + 1] = { 0, #text, "XuePickerBufferSelected", 90 }
    spans[#spans + 1] = { 0, math.min(pointer_end, #text), "XuePickerBufferStrong", 95 }
    if #text > gutter_end then
      spans[#spans + 1] = { gutter_end, #text, "XuePickerBufferStrong", 95 }
    end
  end
  return text, spans
end

return M
