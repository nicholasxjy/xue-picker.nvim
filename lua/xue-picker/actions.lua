local M = {}
function M.open(items, action, location)
  if #items > 1 then
    local entries = {}
    for _, item in ipairs(items) do
      entries[#entries + 1] = {
        filename = item.path,
        bufnr = item.bufnr,
        lnum = item.lnum or 1,
        col = (item.col or 0) + 1,
        text = item.text,
      }
    end
    vim.fn.setqflist({}, " ", { title = "XuePicker", items = entries })
    vim.cmd("copen")
    return
  end
  local item = items[1]
  if not item then
    return
  end
  if action == "tab" then
    vim.cmd("tabnew")
  elseif action == "split" then
    vim.cmd("split")
  elseif action == "vsplit" then
    vim.cmd("vsplit")
  end
  if item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
    vim.api.nvim_set_current_buf(item.bufnr)
  elseif item.path then
    local buf = vim.fn.bufadd(item.path)
    vim.fn.bufload(buf)
    vim.api.nvim_set_current_buf(buf)
  end
  local row, col = item.lnum, item.col
  if location then
    row, col = location[1] or row, location[2] and location[2] - 1 or col
  end
  if row then
    row = math.max(1, math.min(row, vim.api.nvim_buf_line_count(0)))
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
    vim.api.nvim_win_set_cursor(0, { row, math.max(0, math.min(col or 0, #line)) })
    vim.cmd("normal! zvzz")
  end
end
return M
