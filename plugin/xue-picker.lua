if vim.g.loaded_xue_picker then
  return
end
vim.g.loaded_xue_picker = true
vim.api.nvim_create_user_command("XuePicker", function(cmd)
  local builtin = require("xue-picker.builtin")
  local name = cmd.args ~= "" and cmd.args or "smart"
  if name == "resume" then
    require("xue-picker").resume()
    return
  end
  if not vim.tbl_contains(builtin.names, name) then
    error("未知 XuePicker builtin: " .. name)
  end
  builtin[name]()
end, {
  nargs = "?",
  complete = function(prefix)
    local names = vim.list_extend({ "resume" }, require("xue-picker.builtin").names)
    return vim.tbl_filter(function(name)
      return name:sub(1, #prefix) == prefix
    end, names)
  end,
  desc = "Open XuePicker",
})
