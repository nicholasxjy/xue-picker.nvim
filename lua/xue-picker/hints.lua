local U = require("xue-picker.util")
local M = {}

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
    require("xue-picker.highlights").default(name, fallback, targets)
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
  return require("xue-picker.text").clip(text, spans, width, "XuePickerHintSeparator")
end

return M
