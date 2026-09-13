local api = vim.api
local M = {}
local previous

function M.get()
  local sessions = package.loaded["xue-picker.session"]
  local s = sessions and sessions.active
  if not s or s.closed then
    return nil
  end
  return {
    name = s.opts.name or "picker",
    cwd = s.opts.cwd,
    query = s.query,
    index = #s.results > 0 and s.index or 0,
    count = #s.results,
    total = math.max(#s.items, #s.results),
    selected = vim.tbl_count(s.selected),
    loading = s.loading == true,
    searching = s.searching == true,
    error = s.error,
    truncated = s.truncated == true,
    backend = s.backend,
  }
end

function M.text()
  local state = M.get()
  if not state then
    return ""
  end
  local parts = {
    "XuePicker " .. require("xue-picker.util").clean(state.name),
    ("%d/%d"):format(state.count, state.total),
  }
  if state.selected > 0 then
    parts[#parts + 1] = state.selected .. " selected"
  end
  if state.backend then
    parts[#parts + 1] = state.backend
  end
  if state.error then
    parts[#parts + 1] = "Failed"
  elseif state.loading then
    parts[#parts + 1] = "Loading"
  elseif state.searching then
    parts[#parts + 1] = "Searching"
  end
  if state.truncated then
    parts[#parts + 1] = "Truncated"
  end
  return require("xue-picker.util").clean(table.concat(parts, " · "))
end

function M.open(s)
  if s.opts.statusline == false then
    return
  end
  s.statusline_laststatus = vim.o.laststatus
  vim.o.laststatus = 3
  -- Only the disposable input window owns this expression. %{} keeps text
  -- returned by custom picker names from being interpreted as statusline codes.
  vim.wo[s.ui.wins.input].statusline = ' %<%{v:lua.require("xue-picker").statusline()} '
end

function M.close(s)
  if s.statusline_laststatus ~= nil and vim.o.laststatus == 3 then
    vim.o.laststatus = s.statusline_laststatus
  end
end

function M.update()
  local state = M.get()
  if vim.deep_equal(previous, state) then
    return
  end
  previous = state
  vim.cmd("redrawstatus")
  api.nvim_exec_autocmds("User", { pattern = "XuePickerUpdate", modeline = false })
end

return M
