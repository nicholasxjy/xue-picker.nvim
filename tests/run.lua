local root = vim.fn.getcwd()
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local job = vim.fn.jobstart(
  { vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "--noplugin" },
  {
    rpc = true,
    env = { XDG_DATA_HOME = temp, XDG_CACHE_HOME = temp, XDG_STATE_HOME = temp },
  }
)
assert(job > 0)
vim.rpcrequest(job, "nvim_ui_attach", 120, 40, { rgb = true })
local ok, results = pcall(
  vim.rpcrequest,
  job,
  "nvim_exec_lua",
  "vim.opt.rtp:prepend(...); return dofile((...)..'/tests/spec.lua')",
  { root }
)
pcall(vim.fn.jobstop, job)
vim.fn.delete(temp, "rf")
if not ok then
  error(results)
end
local failures = 0
for _, result in ipairs(results) do
  print((result.ok and "PASS " or "FAIL ") .. result.name)
  if not result.ok then
    failures = failures + 1
    print(result.error)
  end
end
print(("%d tests, %d failed"):format(#results, failures))
if failures > 0 then
  vim.cmd("cquit")
end
