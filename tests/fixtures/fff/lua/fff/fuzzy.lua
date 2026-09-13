if vim.env.XUE_TEST_FFF_MODE == "missing_native" then
  error("fixture native library missing")
end
return {}
