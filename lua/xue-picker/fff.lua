local M = {}

function M.search_config()
  local config = require("fff.conf").get()
  -- Only backend settings cross RPC; the full config also contains UI callbacks.
  local settings = {}
  for _, key in ipairs({
    "max_threads",
    "follow_symlinks",
    "enable_home_dir_scanning",
    "enable_fs_root_scanning",
    "frecency",
    "history",
  }) do
    settings[key] = vim.deepcopy(config[key])
  end
  for _, key in ipairs({ "frecency", "history" }) do
    settings[key].db_path = require("xue-picker.util").path(settings[key].db_path)
  end
  return settings
end

function M.highlights()
  local ok, highlights = pcall(require, "fff.highlights")
  if ok then
    highlights.setup()
  end
end

function M.style(item, session, current)
  if not session.opts.git.enabled or not item.git_status then
    return
  end
  local highlights = require("fff.highlights")
  local config = require("fff.conf").get()
  local sign, group = " ", current and config.hl.cursor or nil
  if highlights.should_show_git_border(item.git_status) then
    sign = highlights.get_git_border_char(item.git_status)
    group = highlights.get_git_sign_highlight(item.git_status, current, config.hl.cursor)
  end
  if session.selected[item.id] then
    sign = "▊"
    group = current and config.hl.selected_active or config.hl.selected
  end
  local filename
  local is_current_file = item.fff_score and (item.fff_score.current_file_penalty or 0) < 0
  if config.git.status_text_color and not is_current_file then
    filename = highlights.get_git_text_highlight(item.git_status)
    filename = filename ~= "" and filename or nil
  end
  return {
    prefix = sign .. " ",
    spans = group and { { 0, #sign, group, 150 } } or {},
    filename = filename,
    cursor = config.hl.cursor,
  }
end

return M
