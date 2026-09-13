local M = {}

M.defaults = {
  prompt = "> ",
  pointer = "▌",
  marker = "┃",
  gutter = "▌",
  icons = "auto",
  hint = true,
  statusline = true,
  path_format = "filename_first", -- or "relative", or function(item, cwd)
  layout = { height = 0.4, max_height = 18, preview_width = 0.5, wide = 100, min_preview = 6 },
  preview = { enabled = false, debounce_ms = 60, max_bytes = 1048576, max_lines = 2000 },
  performance = { slice_ms = 4, render_ms = 16, cache_dirs = 3, cache_entries = 200000 },
  scan = { cmd = "rg", args = {}, hidden = true, ignore = true, follow = false, globs = {} },
  matcher = {
    fuzzy = true,
    smartcase = true,
    ignorecase = true,
    filename_bonus = true,
    cwd_bonus = true,
    frecency = false,
    history_bonus = false,
  },
  frecency = { half_life = 2592000, max_size = 10000, save_delay_ms = 1000 },
  sort = true,
  git = { enabled = true, modified_bonus = false },
  filter = { cwd = false },
  highlights = {
    XuePickerNormal = { link = "FzfLuaNormal", default = true },
    XuePickerPrompt = { link = "FzfLuaFzfPrompt", default = true },
    XuePickerQuery = { link = "FzfLuaFzfQuery", default = true },
    XuePickerLivePrompt = { link = "FzfLuaLivePrompt", default = true },
    XuePickerMatch = { link = "FzfLuaFzfMatch", default = true },
    XuePickerIcon = { link = "FzfLuaNormal", default = true },
    XuePickerFilename = { link = "FzfLuaFilePart", default = true },
    XuePickerDirectory = { link = "FzfLuaDirPart", default = true },
    XuePickerLineNr = { link = "FzfLuaPathLineNr", default = true },
    XuePickerColNr = { link = "FzfLuaPathColNr", default = true },
    XuePickerSelected = { link = "FzfLuaFzfCursorLine", default = true },
    XuePickerPointer = { link = "FzfLuaFzfPointer", default = true },
    XuePickerMarker = { link = "FzfLuaFzfMarker", default = true },
    XuePickerGutter = { fg = "bg", default = true },
    XuePickerStrong = { bold = true, default = true },
    XuePickerHint = { link = "FzfLuaHeaderText", default = true },
    XuePickerHintBind = { link = "FzfLuaHeaderBind", default = true },
    XuePickerHintSeparator = { link = "FzfLuaFzfHeader", default = true },
    XuePickerCount = { link = "FzfLuaFzfInfo", default = true },
    XuePickerBufferNumber = { link = "FzfLuaBufNr", default = true },
    XuePickerBufferCurrent = { link = "FzfLuaBufFlagCur", default = true },
    XuePickerBufferAlternate = { link = "FzfLuaBufFlagAlt", default = true },
    XuePickerBufferLineNr = { link = "FzfLuaPathLineNr", default = true },
    XuePickerBufferHeader = { link = "FzfLuaFzfHeader", default = true },
    XuePickerBufferSelected = { link = "FzfLuaFzfCursorLine", default = true },
    XuePickerBufferMatch = { link = "FzfLuaFzfMatch", default = true },
    XuePickerBufferPointer = { link = "FzfLuaFzfPointer", default = true },
    XuePickerBufferMarker = { link = "FzfLuaFzfMarker", default = true },
    XuePickerBufferGutter = { fg = "bg", default = true },
    XuePickerBufferStrong = { bold = true, default = true },
    XuePickerError = { link = "DiagnosticError", default = true },
    XuePickerGit = { link = "DiffChange", default = true },
    XuePickerGroup = { link = "FzfLuaHeaderText", default = true },
    XuePickerGrepPath = { link = "FzfLuaFilePart", default = true },
    XuePickerPreviewLine = { link = "FzfLuaCursorLine", default = true },
    XuePickerDiagnosticError = { link = "DiagnosticSignError", default = true },
    XuePickerDiagnosticWarn = { link = "DiagnosticSignWarn", default = true },
    XuePickerDiagnosticInfo = { link = "DiagnosticSignInfo", default = true },
    XuePickerDiagnosticHint = { link = "DiagnosticSignHint", default = true },
    XuePickerDiagnosticCode = { link = "Comment", default = true },
    XuePickerBorder = { link = "FzfLuaBorder", default = true },
  },
  actions = {},
  keymaps = {
    next = { "<C-n>", "<Down>", "<Tab>" },
    previous = { "<C-p>", "<Up>", "<S-Tab>" },
    accept = { "<CR>", "<C-y>" },
    close = { "<Esc>", "<C-c>" },
    split = { "<C-s>" },
    vsplit = { "<C-v>" },
    tab = { "<C-t>" },
    toggle = { "<C-x>" },
    toggle_all = { "<C-a>" },
    delete = { "<C-d>" },
    preview = { "<C-o>" },
    refresh = { "<C-r>" },
  },
}
M.pickers = {
  files = { prompt = "Files> ", cwd_prompt = true, cwd_prompt_shorten_len = 32, cwd_prompt_shorten_val = 1 },
  smart = {
    prompt = "Files> ",
    cwd_prompt = true,
    cwd_prompt_shorten_len = 32,
    cwd_prompt_shorten_val = 1,
    matcher = false,
    debounce_ms = 30,
    max_results = 20000,
    fff = { ready_timeout_ms = 10000, request_timeout_ms = 1000, idle_timeout_ms = 60000 },
    filter = { cwd = true },
  },
  diagnostics = {
    prompt = "Diagnostics> ",
    scope = "workspace",
    sort = true,
    icons = false,
    git = { enabled = false },
    diag_icons = true,
    diag_source = true,
    diag_code = true,
    color_icons = true,
    color_headings = true,
    multiline = 2,
    signs = {},
  },
  buffers = {
    prompt = "Buffers> ",
    sort = false,
    force = false,
    path_format = "relative",
    filename_only = false,
    sort_lastused = true,
    show_unloaded = true,
    show_unlisted = false,
    ignore_current_buffer = false,
    git = { enabled = false },
  },
  oldfiles = { prompt = "Oldfiles> ", sort = false },
  marks = { prompt = "Marks> ", sort = false },
  history = { prompt = "Command history> ", type = "cmd", sort = false },
  git_files = { prompt = "GitFiles> " },
  manpages = { prompt = "Man> " },
  ui_select = { prompt = "Select one of> " },
  ui_input = { prompt = "Input> " },
  live_grep = {
    prompt = "Grep> ",
    backend = "auto",
    fallback = true,
    mode = "regex",
    smartcase = true,
    debounce_ms = 80,
    max_results = 20000,
    sort = false,
    max_file_size = 10485760,
    globs = {},
    fff = {
      page_size = 256,
      time_budget_ms = 8,
      ready_timeout_ms = 150,
      request_timeout_ms = 1000,
      idle_timeout_ms = 60000,
    },
    ripgrep = { cmd = "rg", args = {} },
  },
}

-- Lists, including the empty table, replace; records merge recursively.
function M.merge(...)
  local out = {}
  for i = 1, select("#", ...) do
    for key, value in pairs(select(i, ...) or {}) do
      if key == "items" then
        out[key] = value -- Candidate arrays can contain 100,000 entries and opaque user values.
      elseif key == "highlights" and type(value) == "table" and not vim.islist(value) then
        -- Each definition replaces the previous one: inherited links ignore explicit colors.
        out[key] = vim.tbl_extend("force", type(out[key]) == "table" and out[key] or {}, vim.deepcopy(value))
      elseif type(value) == "table" and not vim.islist(value) then
        out[key] = M.merge(type(out[key]) == "table" and out[key] or {}, value)
      else
        out[key] = type(value) == "table" and vim.deepcopy(value) or value
      end
    end
  end
  return out
end

M.user = {}
function M.setup(opts)
  M.user = opts or {}
end
function M.resolve(name, opts)
  local picker = (M.user.pickers or {})[name]
  local resolved = M.merge(M.defaults, M.pickers[name], M.user.defaults, picker, opts)
  local custom_prompt = (opts or {}).prompt ~= nil
    or (picker or {}).prompt ~= nil
    or (M.user.defaults or {}).prompt ~= nil
  if not custom_prompt then
    if resolved.cwd_prompt then
      local U = require("xue-picker.util")
      local cwd, current = U.cwd(resolved.cwd), U.cwd()
      local path = cwd ~= current and U.inside(cwd, current) and U.relative(cwd, current) or cwd
      local home = U.path(vim.uv.os_homedir())
      if U.inside(path, home) then
        path = "~" .. path:sub(#home + 1)
      end
      local limit = tonumber(resolved.cwd_prompt_shorten_len)
      if limit and #path >= limit then
        path = vim.fn.pathshorten(path, math.max(1, tonumber(resolved.cwd_prompt_shorten_val) or 1))
      end
      resolved.prompt = path:gsub("/$", "") .. "/"
    elseif name == "history" and resolved.type == "search" then
      resolved.prompt = "Search history> "
    end
  end
  return resolved
end

function M.bindings(opts, actions)
  local keys, seen = {}, {}
  for _, name in ipairs(vim.tbl_keys(opts.keymaps)) do
    local binding = opts.keymaps[name]
    if actions[name] and binding ~= false then
      assert(type(binding) == "string" or type(binding) == "table", "Invalid keymaps." .. name)
      keys[name] = {}
      for _, lhs in ipairs(type(binding) == "string" and { binding } or binding) do
        assert(type(lhs) == "string" and lhs ~= "", "Invalid key for " .. name)
        local code = vim.api.nvim_replace_termcodes(lhs, true, true, true)
        assert(
          not seen[code] or seen[code] == name,
          ("XuePicker key conflict: %s (%s / %s)"):format(lhs, seen[code] or "", name)
        )
        if not seen[code] then
          keys[name][#keys[name] + 1] = lhs
          seen[code] = name
        end
      end
    end
  end
  return keys
end
return M
