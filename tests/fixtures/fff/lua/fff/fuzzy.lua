if vim.env.XUE_TEST_FFF_MODE == "missing_native" then
  error("fixture native library missing")
end
return {
  wait_for_initial_scan = function()
    assert(require("fff").index_started, "index must be started before waiting")
    return vim.env.XUE_TEST_FFF_MODE ~= "scan_timeout"
  end,
}
