local M = {}
function M.check()
  vim.health.start("xue-picker.nvim")
  local core, err = require("xue-picker.ui").capability()
  if core then
    vim.health.ok("Neovim 0.12+ / vim._core.ui2 is available")
  else
    vim.health.error(err)
  end
  local opts = require("xue-picker.config").resolve("live_grep")
  if vim.fn.executable(opts.ripgrep.cmd) == 1 then
    vim.health.ok("ripgrep: " .. vim.fn.exepath(opts.ripgrep.cmd))
  else
    vim.health.warn("ripgrep is unavailable; install rg for file scanning and grep fallback")
  end
  local fff = require("xue-picker.grep.fff")
  if fff.detect() then
    vim.health.ok("fff Lua entry point: " .. fff.detect())
    local ok, api = pcall(require, "fff")
    if ok and type(api.content_search) == "function" then
      vim.health.ok("fff content_search() API is available")
    else
      vim.health.warn("Incompatible fff API: content_search() is required")
    end
    local native_ok, native = pcall(require, "fff.fuzzy")
    if native_ok and type(native) == "table" then
      vim.health.ok("fff native library loaded successfully")
    else
      vim.health.warn("fff native library is unavailable: " .. tostring(native))
    end
  else
    vim.health.info("fff is not installed (optional); auto will use ripgrep")
  end
  local fallback = require("xue-picker.grep").last_fallback
  if fallback then
    vim.health.info("Latest fallback reason: " .. fallback)
  end
end
return M
