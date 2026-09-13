local api, U = vim.api, require("xue-picker.util")
local M = {}
local managed = {}

function M.highlights()
  local light = vim.o.background == "light"
  local defaults = {
    XuePickerHintBind = { fg = light and "MediumSpringGreen" or "BlanchedAlmond" },
    XuePickerHint = { fg = light and "Brown4" or "Brown1" },
    XuePickerHintSeparator = { link = "Normal" },
  }
  for name, fallback in pairs(defaults) do
    local target = require("xue-picker.config").defaults.highlights[name].link
    local targets = name == "XuePickerHintSeparator" and { target, "FzfLuaTitle", "FzfLuaNormal" }
      or { target }
    for _, candidate in ipairs(targets) do
      if not vim.tbl_isempty(api.nvim_get_hl(0, { name = candidate, link = false, create = false })) then
        fallback = { link = candidate }
        break
      end
    end
    local current = api.nvim_get_hl(0, { name = name, create = false })
    local ours = managed[name] and vim.deep_equal(current, managed[name])
    fallback.default = not ours
    api.nvim_set_hl(0, name, fallback)
    -- Refresh only defaults we installed, preserving theme and setup overrides.
    if ours or vim.tbl_isempty(current) then
      managed[name] = api.nvim_get_hl(0, { name = name })
    end
  end
end

local function key_name(key)
  local special = key:match("^<([^<>]+)>$")
  if special then
    special = special:lower()
    local aliases = { cr = "enter", bs = "backspace", del = "delete", space = "space", lt = "<", bar = "|" }
    local modifiers = { c = "ctrl", a = "alt", m = "alt", s = "shift" }
    key = aliases[special]
      or special:gsub("([cams])%-", function(modifier)
        return modifiers[modifier] .. "-"
      end)
  end
  return U.clean(key == " " and "space" or key)
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

local function clip(text, spans, width)
  -- fzf reserves two columns before headers and one at the right edge.
  local limit = math.max(0, width - 1)
  if vim.fn.strdisplaywidth(text) <= limit then
    return text, spans
  end
  local dots = math.min(2, limit)
  local budget, bytes, columns, finish = limit - dots, 0, 0, 0
  for i = 0, vim.fn.strchars(text, true) - 1 do
    local char = vim.fn.strcharpart(text, i, 1, true)
    local size = vim.fn.strdisplaywidth(char)
    bytes, columns = bytes + #char, columns + size
    if columns > budget then
      break
    end
    finish = bytes
  end
  local clipped = {}
  for _, mark in ipairs(spans) do
    if mark[1] < finish then
      clipped[#clipped + 1] = { mark[1], math.min(mark[2], finish), mark[3] }
    end
  end
  local prefix = text:sub(1, finish)
  local next_char = text:sub(finish + 1):gmatch("[%z\1-\127\194-\244][\128-\191]*")
  local span, offset = 1, finish
  for _ = 1, dots do
    -- fzf applies the replaced characters' ANSI spans to the ellipsis, even
    -- when a replaced character occupied two cells.
    while spans[span] and spans[span][2] <= offset do
      span = span + 1
    end
    local mark = spans[span]
    local group = mark and mark[1] <= offset and mark[3]
      or (offset < #text and "XuePickerNormal" or "XuePickerHintSeparator")
    clipped[#clipped + 1] = { #prefix, #prefix + #"·", group }
    prefix = prefix .. "·"
    offset = offset + #(next_char() or "")
  end
  return prefix, clipped
end

function M.render(s, width)
  local entries = {}
  if not s.error then
    for action, keys in pairs(s.keys) do
      if labels[action] ~= false then
        local label = action == "delete" and s.opts.name == "buffers" and "close" or labels[action] or action
        for _, key in ipairs(keys) do
          entries[#entries + 1] = { key_name(key), U.clean(label) }
        end
      end
    end
    table.sort(entries, function(a, b)
      return a[1] < b[1] or a[1] == b[1] and a[2] < b[2]
    end)
  end
  local text, spans = "", {}
  local function add(value, group)
    if group then
      spans[#spans + 1] = { #text, #text + #value, group }
    end
    text = text .. value
  end
  if s.error or #entries > 0 then
    add("  ")
    add(":: ", "XuePickerHintSeparator")
  end
  for i, entry in ipairs(entries) do
    if i > 1 then
      add("|", "XuePickerHintSeparator")
    end
    add("<", "XuePickerHintSeparator")
    add(entry[1], "XuePickerHintBind")
    add("> to ", "XuePickerHintSeparator")
    add(entry[2], "XuePickerHint")
  end
  if s.error then
    add(U.clean(s.error), "XuePickerError")
  end
  return clip(text, spans, width)
end

return M
