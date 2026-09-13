local api, U = vim.api, require("xue-picker.util")
local M = {}
local ns = api.nvim_create_namespace("XuePicker")
function M.highlights(opts)
  for name, def in pairs(require("xue-picker.config").defaults.highlights) do
    api.nvim_set_hl(0, name, def)
  end
  for name, def in pairs(opts.highlights or {}) do
    api.nvim_set_hl(0, name, def)
  end
end
function M.capability()
  if vim.fn.has("nvim-0.12") ~= 1 then
    return nil, "XuePicker requires Neovim 0.12+"
  end
  local ok, core = pcall(require, "vim._core.ui2")
  if
    not ok
    or type(core.enable) ~= "function"
    or type(core.check_targets) ~= "function"
    or type(core.wins) ~= "table"
  then
    return nil, "This Neovim build lacks a compatible vim._core.ui2"
  end
  return core
end
local function buffer(kind)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden = "nofile", "wipe"
  vim.bo[buf].swapfile, vim.bo[buf].modeline = false, false
  if kind == "input" then
    vim.b[buf].completion = false -- Disable Blink completion while typing a query.
  end
  vim.bo[buf].filetype = "xue-picker-" .. kind
  return buf
end
local function config(row, col, width, height, focusable)
  return {
    relative = "laststatus",
    row = 1 + row,
    col = col,
    width = math.max(1, width),
    height = math.max(1, height),
    focusable = focusable,
    style = "minimal",
    border = "none",
    zindex = 210,
    noautocmd = true,
  }
end
function M.open(session)
  local core, err = M.capability()
  assert(core, err)
  assert(#api.nvim_list_uis() > 0, "XuePicker requires an attached Neovim UI")
  if not core.cmd or core.cfg.enable == false then
    core.enable({ enable = true })
  end
  core.check_targets()
  local self = {
    session = session,
    core = core,
    bufs = {},
    wins = {},
    old_cmdheight = vim.o.cmdheight,
    old_core_height = core.cmdheight,
  }
  setmetatable(self, { __index = M })
  session.ui = self
  M.highlights(session.opts)
  for _, name in ipairs({ "prompt", "input", "list", "hint", "preview" }) do
    self.bufs[name] = buffer(name)
  end
  vim.bo[self.bufs.preview].bufhidden = "hide"
  vim.bo[self.bufs.prompt].bufhidden = "hide"
  session.input_buf = self.bufs.input
  self.input = require("xue-picker.input").new(self)
  self:layout()
  self.input:focus()
  -- Messages are positioned above the reserved picker area. Keep existing ui2
  -- configuration intact and restore the hook only if it is still ours.
  if core.msg and core.msg.set_pos then
    self.original_pos = core.msg.set_pos
    self.position = function(...)
      self.original_pos(...)
      for _, name in ipairs({ "msg", "dialog", "pager" }) do
        local win = core.wins[name]
        if api.nvim_win_is_valid(win) then
          local cfg = api.nvim_win_get_config(win)
          if not cfg.hide then
            api.nvim_win_set_config(
              win,
              { relative = "laststatus", col = cfg.col, row = math.min(0, tonumber(cfg.row) or 0) }
            )
          end
        end
      end
    end
    core.msg.set_pos = self.position
    self.original_show = core.msg.show_msg
    self.show_message = function(target, ...)
      return self.original_show(target == "cmd" and "msg" or target, ...)
    end
    core.msg.show_msg = self.show_message
  end
  return self
end
function M:layout()
  local opts = self.session.opts
  local height = opts.layout.height <= 1 and math.floor(vim.o.lines * opts.layout.height)
    or opts.layout.height
  self.height = math.max(3, math.min(opts.layout.max_height, height, math.max(3, vim.o.lines - 4)))
  vim.o.cmdheight = self.height
  self.core.cmdheight = self.height
  local hint_height = opts.hint == false and 0 or 1
  self.width, self.list_height, self.list_width = vim.o.columns, self.height - 1 - hint_height, vim.o.columns
  local prompt_width = self.input:layout(self.width)
  local layouts = {
    input = { 0, prompt_width, self.width - prompt_width, 1, true },
    list = { 1, 0, self.width, self.list_height, false },
  }
  if prompt_width > 0 then
    layouts.prompt = { 0, 0, prompt_width, 1, false }
  end
  if hint_height > 0 then
    layouts.hint = { self.height - 1, 0, self.width, 1, false }
  end
  if self.session.preview_enabled and self.width >= 40 then
    if self.width >= opts.layout.wide and self.list_height >= opts.layout.min_preview then
      self.list_width = math.floor(self.width * (1 - opts.layout.preview_width))
      layouts.list[3] = self.list_width
      layouts.preview = { 1, self.list_width + 1, self.width - self.list_width - 1, self.list_height, false }
    elseif self.list_height >= opts.layout.min_preview + 3 then
      local half = math.floor(self.list_height / 2)
      self.list_height = half
      layouts.list[4] = half
      layouts.preview = { half + 2, 0, self.width, self.height - half - 2 - hint_height, false }
    end
  end
  for name, layout in pairs(layouts) do
    local cfg = config(unpack(layout))
    if self.wins[name] and api.nvim_win_is_valid(self.wins[name]) then
      cfg.noautocmd = nil
      api.nvim_win_set_config(self.wins[name], cfg)
    else
      self.wins[name] = api.nvim_open_win(self.bufs[name], false, cfg)
      vim.wo[self.wins[name]].winhighlight =
        "Normal:XuePickerNormal,EndOfBuffer:XuePickerNormal,Search:XuePickerNormal"
      vim.wo[self.wins[name]].wrap = false
    end
  end
  for _, name in ipairs({ "preview", "hint", "prompt" }) do
    if not layouts[name] and self.wins[name] then
      -- Keep scratch buffers across layout toggles.
      vim.bo[self.bufs[name]].bufhidden = "hide"
      pcall(api.nvim_win_close, self.wins[name], true)
      self.wins[name] = nil
    end
  end
end
function M:query(text)
  return self.input:set(text)
end
local function highlight(buf, row, first, last, group, priority)
  if last > first then
    api.nvim_buf_set_extmark(
      buf,
      ns,
      row,
      first,
      { end_col = last, hl_group = group, priority = priority or 150 }
    )
  end
end
local function icon(item, opts)
  if opts.icons == false then
    return ""
  end
  if type(opts.icons) == "function" then
    local value, group = opts.icons(item)
    return U.clean(value or ""), group
  end
  if item.path then
    local mini = package.loaded["mini.icons"]
    if mini then
      local value, group = mini.get("file", item.path)
      return value .. " ", group
    end
    local devicons = package.loaded["nvim-web-devicons"]
    if devicons then
      local value, group = devicons.get_icon(vim.fs.basename(item.path), nil, { default = true })
      return (value or "·") .. " ", group
    end
  end
  return ""
end
-- Map logical bytes to rendered bytes, including escaped control characters.
local function append(text, input, offset, map, logical)
  for first, char in input:gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do
    local clean = U.clean(char)
    for b = first, first + #char - 1 do
      map[logical + b - 1] = { offset + #text, offset + #text + #clean }
    end
    text = text .. clean
  end
  return text
end
local function path_spans(text, offset, spans, directory_group)
  local directory = text:match("^(.*[/\\])") or ""
  if #directory > 0 then
    spans[#spans + 1] = { offset, offset + #directory, directory_group or "XuePickerDirectory" }
  end
  -- Filename styling sits below search matches and above the selected row.
  spans[#spans + 1] = { offset + #directory, offset + #text, "XuePickerFilename", 100 }
end
local function hint_key(key)
  local special = key:match("^<([^<>]+)>$")
  if special then
    special = special:lower()
    local aliases = { cr = "enter", bs = "backspace", del = "delete" }
    local modifiers = { c = "ctrl", a = "alt", m = "alt", s = "shift" }
    key = aliases[special]
      or special:gsub("([cams])%-", function(modifier)
        return modifiers[modifier] .. "-"
      end)
  end
  return "<" .. U.clean(key) .. ">"
end
function M:format(item, index)
  local s, opts = self.session, self.session.opts
  if opts.format then
    local value, spans = opts.format(item, { width = self.list_width, index = index, session = s })
    return U.clean(value), spans or {}
  end
  local grep = opts.name == "live_grep"
  local prefix = (index == s.index and opts.pointer or " ")
    .. " "
    .. (s.selected[item.id] and opts.marker or " ")
    .. " "
  if opts.name == "diagnostics" then
    return require("xue-picker.diagnostics").format(item, s, self.list_width, prefix, icon(item, opts))
  end
  local text, map, spans, right_directory = "", {}, {}, nil
  if grep and item.lnum then
    local line = ("%" .. (self.line_width or 1) .. "d"):format(item.lnum)
    local column = ("%" .. (self.column_width or 1) .. "d"):format((item.col or 0) + 1)
    spans[#spans + 1] = { #prefix, #prefix + #line, "XuePickerLineNr" }
    prefix = prefix .. line .. ":"
    spans[#spans + 1] = { #prefix, #prefix + #column, "XuePickerColNr" }
    prefix = prefix .. column .. "  "
  end
  if not (grep and opts.group) then
    local icon_text, icon_group = icon(item, opts)
    if #icon_text > 0 then
      spans[#spans + 1] = { #prefix, #prefix + #icon_text, icon_group or "XuePickerIcon" }
      prefix = prefix .. icon_text
    end
  end
  if not grep and type(opts.path_format) == "function" and item.path then
    text = U.clean(opts.path_format(item, opts.cwd))
    path_spans(text, #prefix, spans)
  elseif item.path and not item.lnum and opts.path_format == "filename_first" then
    local dir, name = item.text:match("^(.*[/\\])([^/\\]+)$")
    name = name or item.text
    text = append(text, name, #prefix, map, #item.text - #name)
    spans[#spans + 1] = { #prefix, #prefix + #text, "XuePickerFilename", 100 }
    if dir and (opts.name == "files" or opts.name == "smart") then
      right_directory = dir
    elseif dir then
      text = text .. "  "
      local start = #prefix + #text
      text = append(text, dir, #prefix, map, 0)
      spans[#spans + 1] = { start, #prefix + #text, "XuePickerDirectory" }
    end
  else
    text = append(text, item.text, #prefix, map, 0)
    if item.path and not item.lnum then
      path_spans(text, #prefix, spans)
    end
  end
  if item.lnum then
    if not grep then
      text = text .. ("  :%d:%d"):format(item.lnum, (item.col or 0) + 1)
    end
    if item.path and not opts.group and opts.name ~= "marks" then
      local path = U.clean(U.relative(item.path, opts.cwd))
      path_spans(path, #prefix + #text + 2, spans)
      text = text .. "  " .. path
    end
  end
  if item.status then
    text = text .. "  " .. item.status
  end
  if item.path and s.git_status[item.path] then
    local start = #prefix + #text
    text = text .. "  " .. s.git_status[item.path]
    spans[#spans + 1] = { start, #prefix + #text, "XuePickerGit" }
  end
  local directory_start
  if right_directory then
    text = text .. "  "
    directory_start = #prefix + #text
    text = append(text, right_directory, #prefix, map, 0)
    spans[#spans + 1] = { directory_start, #prefix + #text, "XuePickerDirectory" }
  end
  if item.ranges then
    for _, range in ipairs(item.ranges) do
      for b = range[1], range[2] - 1 do
        if map[b] then
          spans[#spans + 1] = { map[b][1], map[b][2], "XuePickerMatch" }
        end
      end
    end
  elseif s.ranker then
    for b in pairs(s.ranker:byte_positions(s.query, item)) do
      if map[b] then
        spans[#spans + 1] = { map[b][1], map[b][2], "XuePickerMatch" }
      end
    end
  end
  return prefix .. text, spans, directory_start
end
function M:render()
  local s = self.session
  if s.closed then
    return
  end
  if #s.results > 0 and not s.first_results_at then
    s.first_results_at = vim.uv.hrtime() / 1e6
  end
  local grep = s.opts.name == "live_grep"
  if grep and self.location_results ~= s.results then
    -- Rank publishes a new result array; reuse widths while moving or scrolling.
    self.location_results = s.results
    self.line_width, self.column_width = 1, 1
    for _, item in ipairs(s.results) do
      if item.lnum then
        self.line_width = math.max(self.line_width, #tostring(item.lnum))
        self.column_width = math.max(self.column_width, #tostring((item.col or 0) + 1))
      end
    end
  end
  local lines, marks, directories, selected_row, selected_rows = {}, {}, {}, nil, {}
  local height = self.list_height
  s.offset = math.max(1, math.min(s.offset or 1, math.max(1, #s.results)))
  if s.index < s.offset then
    s.offset = s.index
  end
  if s.index >= s.offset + height - (s.opts.group and 1 or 0) then
    s.offset = math.max(1, s.index - height + (s.opts.group and 2 or 1))
  end
  local function fill()
    lines, marks, directories, selected_row, selected_rows = {}, {}, {}, nil, {}
    local previous
    for i = s.offset, #s.results do
      local item = s.results[i]
      if s.opts.group and item.path ~= previous then
        if #lines >= height - 1 then
          break
        end
        local path = U.clean(
          grep and type(s.opts.path_format) == "function" and s.opts.path_format(item, s.opts.cwd)
            or U.relative(item.path or "", s.opts.cwd)
        )
        local prefix, spans = "  ", {}
        if grep then
          local icon_text, icon_group = icon(item, s.opts)
          if #icon_text > 0 then
            spans[#spans + 1] = { #prefix, #prefix + #icon_text, icon_group or "XuePickerIcon" }
            prefix = prefix .. icon_text
          end
        end
        lines[#lines + 1] = prefix .. path
        if grep then
          spans[#spans + 1] = { #prefix, #prefix + #path, "XuePickerGrepPath" }
        else
          path_spans(path, #prefix, spans, "XuePickerGroup")
        end
        for _, span in ipairs(spans) do
          marks[#marks + 1] = { #lines - 1, unpack(span) }
        end
        previous = item.path
      end
      if #lines >= height then
        break
      end
      local line, spans, directory_start, continuation = self:format(item, i)
      local entry_height = 1
      for _, part in ipairs(continuation or {}) do
        if not part.gap then
          entry_height = entry_height + 1
        end
      end
      if #lines > 0 and #lines + entry_height > height then
        break
      end
      lines[#lines + 1] = line
      directories[#lines - 1] = directory_start
      for _, span in ipairs(spans) do
        marks[#marks + 1] = { #lines - 1, unpack(span) }
      end
      if i == s.index then
        selected_row = #lines - 1
        selected_rows[#selected_rows + 1] = selected_row
      end
      for _, part in ipairs(continuation or {}) do
        if #lines >= height then
          break
        end
        lines[#lines + 1] = part.text
        for _, span in ipairs(part.spans) do
          marks[#marks + 1] = { #lines - 1, unpack(span) }
        end
        if i == s.index and not part.gap then
          selected_rows[#selected_rows + 1] = #lines - 1
        end
      end
    end
  end
  fill()
  -- Group headings and multiline entries consume rows. Keep the selection visible.
  while #s.results > 0 and not selected_row and s.offset < s.index do
    s.offset = s.offset + 1
    fill()
  end
  -- Align directories to the longest visible row, keeping the column near filenames.
  local directory_edge, padding = 0, {}
  for row in pairs(directories) do
    directory_edge = math.max(directory_edge, vim.fn.strdisplaywidth(lines[row + 1]))
  end
  for row, start in pairs(directories) do
    local line = lines[row + 1]
    padding[row] = directory_edge - vim.fn.strdisplaywidth(line)
    lines[row + 1] = line:sub(1, start) .. string.rep(" ", padding[row]) .. line:sub(start + 1)
  end
  for _, mark in ipairs(marks) do
    local row = mark[1]
    if directories[row] and mark[2] >= directories[row] then
      mark[2], mark[3] = mark[2] + padding[row], mark[3] + padding[row]
    end
  end
  if #lines == 0 then
    local message = s.error or (s.loading and "Loading…" or s.searching and "Searching…" or "No results")
    lines = { grep and not s.error and (s.loading or s.searching) and "" or "  " .. message }
  end
  while #lines < height do
    lines[#lines + 1] = ""
  end
  api.nvim_buf_set_lines(self.bufs.list, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(self.bufs.list, ns, 0, -1)
  for _, row in ipairs(selected_rows) do
    api.nvim_buf_set_extmark(
      self.bufs.list,
      ns,
      row,
      0,
      { line_hl_group = "XuePickerSelected", priority = 90 }
    )
  end
  for _, mark in ipairs(marks) do
    highlight(self.bufs.list, unpack(mark))
  end
  if s.error then
    highlight(self.bufs.list, 0, 0, #lines[1], "XuePickerError")
  end
  local status = s.error and "Failed"
    or not grep and (s.loading and "Loading" or s.searching and "Searching")
    or ""
  local count = (" %s%s %d/%d%s "):format(
    s.backend and s.backend .. " · " or "",
    status,
    #s.results,
    math.max(#s.items, #s.results),
    s.truncated and " · Truncated" or ""
  )
  self.input:render(count)
  if s.opts.hint == false then
    require("xue-picker.statusline").update()
    return
  end
  local labels = {
    accept = false,
    close = false,
    next = false,
    previous = false,
    toggle = "select",
    preview = false,
    refresh = false,
    delete = "delete",
    split = "split",
    vsplit = "vsplit",
    tab = "tab",
    toggle_all = "select all",
  }
  local names = {
    "toggle",
    "delete",
    "split",
    "vsplit",
    "tab",
    "toggle_all",
  }
  for _, name in ipairs(vim.fn.sort(vim.tbl_keys(s.keys))) do
    if labels[name] == nil then
      names[#names + 1] = name
    end
  end
  if s.error then
    names = {}
  end
  local function hints(first_only)
    local text, spans = "", {}
    local function add(value, group)
      spans[#spans + 1] = { #text, #text + #value, group }
      text = text .. value
    end
    for _, name in ipairs(names) do
      local keys = s.keys[name]
      if keys and #keys > 0 then
        add(text == "" and ":: " or "|", "XuePickerHintSeparator")
        for i, key in ipairs(keys) do
          if i > 1 then
            if first_only then
              break
            end
            add("/", "XuePickerHintSeparator")
          end
          add(hint_key(key), "XuePickerHintBind")
        end
        add(" to ", "XuePickerHintSeparator")
        add(U.clean(labels[name] or name), "XuePickerHint")
      end
    end
    if s.error then
      add(text == "" and ":: " or "|", "XuePickerHintSeparator")
      add(U.clean(s.error), "XuePickerError")
    end
    return text, spans
  end
  local hint, hint_spans = hints(false)
  if vim.fn.strdisplaywidth(hint) > self.width then
    hint, hint_spans = hints(true)
  end
  api.nvim_buf_set_lines(self.bufs.hint, 0, -1, false, { hint })
  api.nvim_buf_clear_namespace(self.bufs.hint, ns, 0, -1)
  for _, span in ipairs(hint_spans) do
    highlight(self.bufs.hint, 0, unpack(span))
  end
  require("xue-picker.statusline").update()
end
function M:preview(lines, row)
  if not api.nvim_buf_is_valid(self.bufs.preview) then
    return
  end
  if self.external_buf and api.nvim_buf_is_valid(self.external_buf) then
    api.nvim_buf_clear_namespace(self.external_buf, ns, 0, -1)
  end
  self.external_buf = nil
  if self.wins.preview and api.nvim_win_get_buf(self.wins.preview) ~= self.bufs.preview then
    api.nvim_win_set_buf(self.wins.preview, self.bufs.preview)
  end
  api.nvim_buf_set_lines(self.bufs.preview, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(self.bufs.preview, ns, 0, -1)
  if row and row >= 1 and row <= #lines then
    api.nvim_buf_set_extmark(self.bufs.preview, ns, row - 1, 0, { line_hl_group = "XuePickerPreviewLine" })
    if self.wins.preview then
      api.nvim_win_set_cursor(self.wins.preview, { row, 0 })
      api.nvim_win_call(self.wins.preview, function()
        vim.cmd("normal! zz")
      end)
    end
  end
end
function M:external_preview(info)
  if not self.wins.preview then
    return
  end
  if not info or not info.buf or not api.nvim_buf_is_valid(info.buf) then
    self:preview({ "No preview" })
    return
  end
  if self.external_buf and api.nvim_buf_is_valid(self.external_buf) then
    api.nvim_buf_clear_namespace(self.external_buf, ns, 0, -1)
  end
  self.external_buf = info.buf
  api.nvim_win_set_buf(self.wins.preview, info.buf)
  local pos = info.pos or { 1, 0 }
  local row = math.max(1, math.min(pos[1], api.nvim_buf_line_count(info.buf)))
  local line = api.nvim_buf_get_lines(info.buf, row - 1, row, false)[1] or ""
  api.nvim_win_set_cursor(self.wins.preview, { row, math.min(pos[2], #line) })
  if info.pos_end then
    api.nvim_buf_set_extmark(info.buf, ns, row - 1, math.min(pos[2], #line), {
      end_row = info.pos_end[1] - 1,
      end_col = info.pos_end[2],
      hl_group = "XuePickerMatch",
      strict = false,
    })
  end
end
function M:close()
  if self.external_buf and api.nvim_buf_is_valid(self.external_buf) then
    api.nvim_buf_clear_namespace(self.external_buf, ns, 0, -1)
  end
  if self.original_show and self.core.msg.show_msg == self.show_message then
    self.core.msg.show_msg = self.original_show
  end
  if self.original_pos and self.core.msg.set_pos == self.position then
    self.core.msg.set_pos = self.original_pos
  end
  for _, win in pairs(self.wins) do
    pcall(api.nvim_win_close, win, true)
  end
  for _, buf in pairs(self.bufs) do
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  vim.o.cmdheight = self.old_cmdheight
  self.core.cmdheight = self.old_core_height
  if self.core.msg then
    pcall(self.core.msg.set_pos)
  end
end
return M
