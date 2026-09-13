local api, U = vim.api, require("xue-picker.util")
local M = {}
local ns = api.nvim_create_namespace("XuePickerInput")

function M.new(ui)
  local self = setmetatable({ ui = ui, session = ui.session }, { __index = M })
  api.nvim_buf_attach(ui.bufs.input, false, {
    on_lines = function()
      if self.session.closed or self.setting or self.pending then
        return
      end
      self.pending = true
      vim.schedule(function()
        self.pending = false
        if self.session.closed or not api.nvim_buf_is_valid(ui.bufs.input) then
          return
        end
        local lines = api.nvim_buf_get_lines(ui.bufs.input, 0, -1, false)
        local value = table.concat(lines, " ")
        if #lines > 1 then
          self:set(value)
        end
        self.session:set_query(value, true)
      end)
    end,
  })
  for action, keys in pairs(self.session.keys) do
    for _, lhs in ipairs(keys) do
      vim.keymap.set({ "i", "n" }, lhs, function()
        self.session:act(action)
      end, { buffer = ui.bufs.input, silent = true, nowait = true, desc = "XuePicker " .. action })
    end
  end
  vim.keymap.set("n", "<Plug>(XuePickerInputStart)", function()
    if not self.session.closed and api.nvim_get_current_win() == ui.wins.input then
      return "A"
    end
    return ""
  end, { buffer = ui.bufs.input, expr = true, silent = true })
  return self
end

function M:layout(width)
  self.prompt = U.clean(self.session.opts.prompt)
  local available = math.max(0, width - math.min(8, math.max(1, math.floor(width / 2))))
  local text, columns = "", 0
  for char in self.prompt:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local size = vim.fn.strdisplaywidth(char)
    if columns + size > available then
      break
    end
    text, columns = text .. char, columns + size
  end
  self.width, self.prompt_width = width - columns, columns
  local buf = self.ui.bufs.prompt
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #text, hl_group = "XuePickerPrompt" })
  return columns
end

function M:focus()
  local win = self.ui.wins.input
  for name, value in pairs({
    cursorline = false,
    cursorcolumn = false,
    colorcolumn = "",
    list = false,
    spell = false,
    wrap = false,
    sidescrolloff = 0,
    scrolloff = 0,
    virtualedit = "onemore",
  }) do
    vim.wo[win][name] = value
  end
  api.nvim_set_current_win(win)
end

function M:start()
  self:focus()
  local function enter()
    if not self.session.closed and api.nvim_get_current_win() == self.ui.wins.input then
      local text = api.nvim_buf_get_lines(self.ui.bufs.input, 0, 1, false)[1] or ""
      api.nvim_win_set_cursor(self.ui.wins.input, { 1, #text })
      vim.cmd("startinsert!")
    end
  end
  if api.nvim_get_mode().mode:sub(1, 1) == "i" then
    -- A replaced session's pending stopinsert must finish before the new input starts.
    api.nvim_create_autocmd("InsertLeave", {
      group = self.session.augroup,
      once = true,
      callback = function()
        -- Enter before queued user input can be interpreted as Normal-mode commands.
        if not self.session.closed and api.nvim_get_current_win() == self.ui.wins.input then
          api.nvim_feedkeys(
            api.nvim_replace_termcodes("<Plug>(XuePickerInputStart)", true, false, true),
            "mi",
            false
          )
        end
      end,
    })
    vim.cmd("stopinsert")
  else
    enter()
  end
end

function M:set(value)
  local text = tostring(value or ""):gsub("[\r\n]", " ")
  self.setting = true
  api.nvim_buf_set_lines(self.ui.bufs.input, 0, -1, false, { text })
  api.nvim_win_set_cursor(self.ui.wins.input, { 1, #text })
  self.setting = false
  return text
end

function M:render(count)
  local s, buf = self.session, self.ui.bufs.input
  if self.prompt ~= U.clean(s.opts.prompt) then
    self.ui:layout()
  end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local function highlight(first, last, group, priority)
    first, last = math.max(0, first), math.min(#s.query, last)
    if last > first then
      api.nvim_buf_set_extmark(buf, ns, 0, first, {
        end_col = last,
        hl_group = group,
        priority = priority or 150,
      })
    end
  end
  highlight(0, #s.query, s.opts.name == "live_grep" and "XuePickerLivePrompt" or "XuePickerQuery", 100)
  if s.opts.highlight then
    local handler = type(s.opts.highlight) == "string" and vim.fn[s.opts.highlight] or s.opts.highlight
    for _, span in ipairs(handler(s.query) or {}) do
      highlight(span[1], span[2], span[3])
    end
  end
  if self.width > vim.fn.strdisplaywidth(s.query .. count) + 2 then
    api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_text = { { count, "XuePickerCount" } },
      virt_text_pos = "right_align",
    })
  end
end

return M
