local M = {}
function M.check()
  vim.health.start("xue-picker.nvim")
  local core, err = require("xue-picker.ui").capability()
  if core then
    vim.health.ok("Neovim 0.12+ / vim._core.ui2 可用")
  else
    vim.health.error(err)
  end
  local opts = require("xue-picker.config").resolve("live_grep")
  if vim.fn.executable(opts.ripgrep.cmd) == 1 then
    vim.health.ok("ripgrep: " .. vim.fn.exepath(opts.ripgrep.cmd))
  else
    vim.health.warn("ripgrep 不可用；安装 rg 以支持文件扫描及 grep 回退")
  end
  local fff = require("xue-picker.grep.fff")
  if fff.detect() then
    vim.health.ok("fff Lua 入口: " .. fff.detect())
    local ok, api = pcall(require, "fff")
    if ok and type(api.content_search) == "function" then
      vim.health.ok("fff content_search() 接口可用")
    else
      vim.health.warn("fff API 不兼容: 需要 content_search()")
    end
    local native_ok, native = pcall(require, "fff.fuzzy")
    if native_ok and type(native) == "table" then
      vim.health.ok("fff 原生库可加载")
    else
      vim.health.warn("fff 原生库不可用: " .. tostring(native))
    end
  else
    vim.health.info("fff 未安装（可选依赖）；auto 将使用 ripgrep")
  end
  local fallback = require("xue-picker.grep").last_fallback
  if fallback then
    vim.health.info("最近回退原因: " .. fallback)
  end
end
return M
