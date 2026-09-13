local api = vim.api
local M, managed = {}, {}

function M.default(name, fallback, targets)
  local target = require("xue-picker.config").defaults.highlights[name].link
  for _, candidate in ipairs(targets or { target }) do
    if not vim.tbl_isempty(api.nvim_get_hl(0, { name = candidate, link = false, create = false })) then
      fallback = { link = candidate }
      break
    end
  end
  local current = api.nvim_get_hl(0, { name = name, create = false })
  local ours = managed[name] and vim.deep_equal(current, managed[name])
  fallback.default = not ours
  api.nvim_set_hl(0, name, fallback)
  if ours or vim.tbl_isempty(current) then
    managed[name] = api.nvim_get_hl(0, { name = name })
  end
end

return M
