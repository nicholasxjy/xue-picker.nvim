local U = require("xue-picker.util")
local M, Store = {}, {}
Store.__index = Store
function M.new(opts)
  opts = opts or {}
  local self = setmetatable({
    data = opts.data or {},
    path = opts.path,
    now = opts.now or os.time,
    stat = opts.stat or vim.uv.fs_stat,
    lambda = math.log(2) / (opts.half_life or 2592000),
    max_size = opts.max_size or 10000,
  }, Store)
  if self.path then
    local ok, lines = pcall(vim.fn.readfile, self.path)
    local decoded, data = false, nil
    if ok then
      decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    end
    if decoded and type(data) == "table" then
      for path, deadline in pairs(data) do
        if
          type(path) == "string"
          and type(deadline) == "number"
          and deadline == deadline
          and math.abs(deadline) < 1e12
        then
          self.data[path] = deadline
        end
      end
    end
  end
  return self
end
function Store:to_deadline(value)
  return self.now() + math.log(value) / self.lambda
end
function Store:to_score(deadline)
  return math.exp(self.lambda * (deadline - self.now()))
end
function Store:seed(item)
  if not item.recent and not item.info then
    return 0
  end
  local used = item.info and item.info.lastused or item.lastused
  if not used then
    local st = self.stat(item.path)
    used = st and st.mtime.sec
  end
  return used and math.exp(-self.lambda * (self.now() - used)) or 0
end
function Store:get(item, opts)
  opts = opts or {}
  local path = opts.normalized and item.path or U.path(item.path)
  if not path then
    return 0
  end
  if self.data[path] then
    return self:to_score(self.data[path])
  end
  return opts.seed == false and 0 or self:seed(item)
end
function Store:visit(item, value)
  local path = U.path(item.path)
  if not path then
    return
  end
  self.data[path] = self:to_deadline(self:get(item, { seed = false }) + (value or 1))
  self.dirty = true
end
function Store:save()
  if not self.path or not self.dirty then
    return true
  end
  local entries = {}
  for path, deadline in pairs(self.data) do
    entries[#entries + 1] = { path, deadline }
  end
  table.sort(entries, function(a, b)
    return a[2] > b[2]
  end)
  for i = self.max_size + 1, #entries do
    self.data[entries[i][1]] = nil
  end
  vim.fn.mkdir(vim.fs.dirname(self.path), "p")
  local temp = self.path .. "." .. vim.uv.os_getpid() .. ".tmp"
  local fd, err = vim.uv.fs_open(temp, "w", 384)
  if not fd then
    return nil, err
  end
  local ok
  ok, err = vim.uv.fs_write(fd, vim.json.encode(self.data), 0)
  vim.uv.fs_close(fd)
  if ok then
    ok, err = vim.uv.fs_rename(temp, self.path)
  end
  if not ok then
    vim.uv.fs_unlink(temp)
    return nil, err
  end
  self.dirty = false
  return true
end
function M.default(opts)
  if M.store then
    return M.store
  end
  opts = require("xue-picker.config").merge(
    opts,
    { path = (opts or {}).path or vim.fn.stdpath("data") .. "/xue-picker/frecency.json" }
  )
  M.store = M.new(opts)
  local group = vim.api.nvim_create_augroup("XuePickerFrecency", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" or not vim.bo[ev.buf].buflisted then
        return
      end
      local path = vim.api.nvim_buf_get_name(ev.buf)
      if path == "" then
        return
      end
      vim.uv.fs_stat(
        path,
        vim.schedule_wrap(function(_, stat)
          if not stat or stat.type ~= "file" then
            return
          end
          M.store:visit({ path = path })
          U.stop(M.timer)
          M.timer = U.later(opts.save_delay_ms or 1000, function()
            M.store:save()
          end)
        end)
      )
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      U.stop(M.timer)
      M.store:save()
    end,
  })
  return M.store
end
return M
