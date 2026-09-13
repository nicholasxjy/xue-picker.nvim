local M = {
  sections = {
    lualine_a = {
      function()
        -- lualine treats component output as statusline syntax.
        return (require("xue-picker").statusline():gsub("%%", "%%%%"))
      end,
    },
  },
  filetypes = { "xue-picker-input" },
}

function M.init()
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("XuePickerLualine", { clear = true }),
    pattern = "XuePickerUpdate",
    callback = function()
      -- A window refresh includes the floating input even without globalstatus.
      require("lualine").refresh({ scope = "window", place = { "statusline" }, force = true })
    end,
  })
end

return M
