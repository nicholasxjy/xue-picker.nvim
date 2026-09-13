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
    return nil, "XuePicker 需要 Neovim 0.12+"
  end
  local ok, core = pcall(require, "vim._core.ui2")
  if
    not ok
    or type(core.enable) ~= "function"
    or type(core.check_targets) ~= "function"
    or type(core.wins) ~= "table"
  then
    return nil, "当前 Neovim 缺少兼容的 vim._core.ui2"
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
  assert(#api.nvim_list_uis() > 0, "XuePicker 需要附着的 Neovim UI")
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
  for _, name in ipairs({ "input", "list", "hint", "preview" }) do
    self.bufs[name] = buffer(name)
  end
  vim.bo[self.bufs.preview].bufhidden = "hide"
  session.input_buf = self.bufs.input
  self:layout()
  api.nvim_set_current_win(self.wins.input)
  vim.wo[self.wins.input].cursorline = false
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
  api.nvim_buf_attach(self.bufs.input, false, {
    on_lines = function()
      if session.closed or self.setting then
        return
      end
      vim.schedule(function()
        if session.closed or not api.nvim_buf_is_valid(self.bufs.input) then
          return
        end
        local lines = api.nvim_buf_get_lines(self.bufs.input, 0, -1, false)
        local value = table.concat(lines, " ")
        if #lines > 1 then
          self:query(value)
        end
        session:set_query(value, true)
      end)
    end,
  })
  for action, keys in pairs(session.keys) do
    for _, lhs in ipairs(keys) do
      vim.keymap.set({ "i", "n" }, lhs, function()
        session:act(action)
      end, { buffer = self.bufs.input, silent = true, nowait = true, desc = "XuePicker " .. action })
    end
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
  self.width, self.list_height, self.list_width = vim.o.columns, self.height - 2, vim.o.columns
  local layouts = {
    input = { 0, 0, self.width, 1, true },
    list = { 1, 0, self.width, self.list_height, false },
    hint = { self.height - 1, 0, self.width, 1, false },
  }
  if self.session.preview_enabled and self.width >= 40 then
    if self.width >= opts.layout.wide and self.list_height >= opts.layout.min_preview then
      self.list_width = math.floor(self.width * (1 - opts.layout.preview_width))
      layouts.list[3] = self.list_width
      layouts.preview = { 1, self.list_width + 1, self.width - self.list_width - 1, self.list_height, false }
    elseif self.list_height >= opts.layout.min_preview + 3 then
      local half = math.floor(self.list_height / 2)
      self.list_height = half
      layouts.list[4] = half
      layouts.preview = { half + 2, 0, self.width, self.height - half - 3, false }
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
  if not layouts.preview and self.wins.preview then
    -- Keep the scratch buffer across layout toggles.
    vim.bo[self.bufs.preview].bufhidden = "hide"
    pcall(api.nvim_win_close, self.wins.preview, true)
    self.wins.preview = nil
  end
end
function M:query(text)
  self.setting = true
  api.nvim_buf_set_lines(self.bufs.input, 0, -1, false, { text })
  api.nvim_win_set_cursor(self.wins.input, { 1, #text })
  self.setting = false
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
function M:format(item, index)
  local s, opts = self.session, self.session.opts
  if opts.format then
    local value, spans = opts.format(item, { width = self.list_width, index = index, session = s })
    return U.clean(value), spans or {}
  end
  local prefix = (index == s.index and opts.pointer or " ")
    .. " "
    .. (s.selected[item.id] and opts.marker or " ")
    .. " "
  local text, map, spans = "", {}, {}
  local icon_text, icon_group = icon(item, opts)
  if #icon_text > 0 then
    spans[#spans + 1] = { #prefix, #prefix + #icon_text, icon_group or "XuePickerIcon" }
    prefix = prefix .. icon_text
  end
  if type(opts.path_format) == "function" and item.path then
    text = U.clean(opts.path_format(item, opts.cwd))
    path_spans(text, #prefix, spans)
  elseif item.path and not item.lnum and opts.path_format == "filename_first" then
    local dir, name = item.text:match("^(.*[/\\])([^/\\]+)$")
    name = name or item.text
    text = append(text, name, #prefix, map, #item.text - #name)
    spans[#spans + 1] = { #prefix, #prefix + #text, "XuePickerFilename", 100 }
    if dir then
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
  if item.lnum then
    text = text .. ("  :%d:%d"):format(item.lnum, (item.col or 0) + 1)
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
  return prefix .. text, spans
end
function M:render()
  local s = self.session
  if s.closed then
    return
  end
  if #s.results > 0 and not s.first_results_at then
    s.first_results_at = vim.uv.hrtime() / 1e6
  end
  local lines, marks, selected_row = {}, {}, nil
  local height = self.list_height
  s.offset = math.max(1, math.min(s.offset or 1, math.max(1, #s.results)))
  if s.index < s.offset then
    s.offset = s.index
  end
  if s.index >= s.offset + height - (s.opts.group and 1 or 0) then
    s.offset = math.max(1, s.index - height + (s.opts.group and 2 or 1))
  end
  local function fill()
    lines, marks, selected_row = {}, {}, nil
    local previous
    for i = s.offset, #s.results do
      local item = s.results[i]
      if s.opts.group and item.path ~= previous then
        if #lines >= height - 1 then
          break
        end
        local path = U.clean(U.relative(item.path or "", s.opts.cwd))
        lines[#lines + 1] = "  " .. path
        local spans = {}
        path_spans(path, 2, spans, "XuePickerGroup")
        for _, span in ipairs(spans) do
          marks[#marks + 1] = { #lines - 1, unpack(span) }
        end
        previous = item.path
      end
      if #lines >= height then
        break
      end
      local line, spans = self:format(item, i)
      lines[#lines + 1] = line
      for _, span in ipairs(spans) do
        marks[#marks + 1] = { #lines - 1, unpack(span) }
      end
      if i == s.index then
        selected_row = #lines - 1
      end
    end
  end
  fill()
  -- Group headings consume rows. Keep the active result visible when scrolling.
  while #s.results > 0 and not selected_row and s.offset < s.index do
    s.offset = s.offset + 1
    fill()
  end
  if #lines == 0 then
    lines =
      { "  " .. (s.error or (s.loading and "加载中…" or s.searching and "搜索中…" or "无结果")) }
  end
  while #lines < height do
    lines[#lines + 1] = ""
  end
  api.nvim_buf_set_lines(self.bufs.list, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(self.bufs.list, ns, 0, -1)
  if selected_row then
    api.nvim_buf_set_extmark(
      self.bufs.list,
      ns,
      selected_row,
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
  api.nvim_buf_clear_namespace(self.bufs.input, ns, 0, -1)
  if s.opts.highlight then
    local handler = type(s.opts.highlight) == "string" and vim.fn[s.opts.highlight] or s.opts.highlight
    for _, span in ipairs(handler(s.query) or {}) do
      highlight(self.bufs.input, 0, math.max(0, span[1]), math.min(#s.query, span[2]), span[3])
    end
  end
  api.nvim_buf_set_extmark(
    self.bufs.input,
    ns,
    0,
    0,
    { virt_text = { { U.clean(s.opts.prompt), "XuePickerPrompt" } }, virt_text_pos = "inline" }
  )
  local status = s.error and "失败" or s.loading and "加载" or s.searching and "搜索" or ""
  local count = (" %s%s %d/%d%s "):format(
    s.backend and s.backend .. " · " or "",
    status,
    #s.results,
    math.max(#s.items, #s.results),
    s.truncated and " · 已截断" or ""
  )
  if self.width > vim.fn.strdisplaywidth(s.query .. s.opts.prompt .. count) + 2 then
    api.nvim_buf_set_extmark(
      self.bufs.input,
      ns,
      0,
      0,
      { virt_text = { { count, "XuePickerCount" } }, virt_text_pos = "right_align" }
    )
  end
  local labels = {
    accept = "打开",
    close = "关闭",
    next = "下一项",
    previous = "上一项",
    toggle = "多选",
    preview = "预览",
    refresh = "刷新",
    delete = "删除",
    split = "分屏",
    vsplit = "竖分",
    tab = "标签",
    toggle_all = "全选",
  }
  local names = {
    "accept",
    "close",
    "next",
    "previous",
    "toggle",
    "preview",
    "refresh",
    "delete",
    "split",
    "vsplit",
    "tab",
    "toggle_all",
  }
  for name in pairs(s.keys) do
    if not labels[name] then
      names[#names + 1] = name
    end
  end
  local function hints(first_only)
    local parts = {}
    for _, name in ipairs(names) do
      local keys = s.keys[name]
      if keys and #keys > 0 then
        parts[#parts + 1] = (first_only and keys[1] or table.concat(keys, "/"))
          .. " "
          .. (labels[name] or name)
      end
    end
    return " " .. table.concat(parts, "  ")
  end
  local hint = hints(false)
  if vim.fn.strdisplaywidth(hint) > self.width then
    hint = hints(true)
  end
  if s.error then
    hint = " "
      .. ((s.keys.close or {})[1] or "")
      .. " 关闭  "
      .. ((s.keys.refresh or {})[1] or "")
      .. " 重试  "
      .. U.clean(s.error)
  end
  api.nvim_buf_set_lines(self.bufs.hint, 0, -1, false, { hint })
  api.nvim_buf_clear_namespace(self.bufs.hint, ns, 0, -1)
  highlight(self.bufs.hint, 0, 0, #hint, s.error and "XuePickerError" or "XuePickerHint")
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
    self:preview({ "无预览" })
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
