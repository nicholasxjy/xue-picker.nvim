local M = {}
function M.get()
  return vim.tbl_deep_extend("force", {
    max_threads = 4,
    follow_symlinks = false,
    enable_home_dir_scanning = true,
    enable_fs_root_scanning = false,
    frecency = { enabled = true, db_path = vim.fn.stdpath("cache") .. "/fff_nvim" },
    history = {
      enabled = true,
      db_path = vim.fn.stdpath("data") .. "/fff_queries",
      min_combo_count = 3,
      combo_boost_score_multiplier = 100,
    },
    git = { status_text_color = false },
    hl = { cursor = "CursorLine", selected = "FFFSelected", selected_active = "FFFSelectedActive" },
  }, vim.g.fff or {})
end
return M
