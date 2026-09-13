local M = {}
local original
function M.setup(opts)
  opts = opts or {}
  require("xue-picker.config").setup(opts)
  original = original or { select = vim.ui.select, input = vim.ui.input }
  vim.ui.select = (opts.ui or {}).select and require("xue-picker.builtin").ui_select or original.select
  vim.ui.input = (opts.ui or {}).input and require("xue-picker.builtin").ui_input or original.input
end
function M.pick(opts)
  opts = require("xue-picker.config").resolve(opts and opts.name, opts)
  opts.cwd = require("xue-picker.util").cwd(opts.cwd)
  return require("xue-picker.session").new(opts)
end
function M.resume()
  local session = require("xue-picker.session")
  if not session.previous then
    return nil
  end
  local previous = session.previous
  return session.new(previous.opts, previous)
end
function M.status()
  return require("xue-picker.statusline").get()
end
function M.statusline()
  return require("xue-picker.statusline").text()
end
return M
