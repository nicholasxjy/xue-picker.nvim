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
  local buf = item.bufnr
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = item.path and vim.fn.bufadd(item.path) or nil
  end
  if buf then
    -- bufadd() leaves files unlisted; tablines and buffer pickers need them listed.
    if vim.bo[buf].buftype == "" then
      vim.bo[buf].buflisted = true
    end
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
