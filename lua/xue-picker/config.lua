local M = {}

M.defaults = {
  prompt = "❯ ",
  pointer = "▸",
  marker = "●",
  icons = "auto",
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
  highlights = {},
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
  smart = { matcher = { frecency = true }, filter = { cwd = true } },
  diagnostics = { scope = "workspace", sort = false },
  buffers = { sort = false, force = false },
  oldfiles = { sort = false },
  marks = { sort = false },
  history = { type = "cmd", sort = false },
  live_grep = {
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
  return M.merge(M.defaults, M.pickers[name], M.user.defaults, (M.user.pickers or {})[name], opts)
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
