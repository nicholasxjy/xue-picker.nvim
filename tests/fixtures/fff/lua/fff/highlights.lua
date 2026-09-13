local M = {}
local kinds = { modified = "Modified", untracked = "Untracked", staged_new = "Staged", deleted = "Deleted" }
function M.setup()
  for _, kind in pairs(kinds) do
    vim.api.nvim_set_hl(0, "FFFGitSign" .. kind, { fg = "#123456", default = true })
    vim.api.nvim_set_hl(0, "FFFGitSign" .. kind .. "Selected", { fg = "#123456", default = true })
    vim.api.nvim_set_hl(0, "FFFGit" .. kind, { fg = "#123456", default = true })
  end
end
function M.should_show_git_border(status)
  return kinds[status] ~= nil
end
function M.get_git_border_char(status)
  return status == "untracked" and "┆" or status == "deleted" and "▁" or "┃"
end
function M.get_git_sign_highlight(status, current)
  return "FFFGitSign" .. kinds[status] .. (current and "Selected" or "")
end
function M.get_git_text_highlight(status)
  return kinds[status] and "FFFGit" .. kinds[status] or ""
end
return M
