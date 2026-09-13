local U, api = require("xue-picker.util"), vim.api
local M, Session = {}, {}
Session.__index = Session
local serial = 0
local function cancel(self, name)
  local fn = self[name]
  self[name] = nil
  if fn then
    pcall(fn)
  end
end
function Session:draw()
  if self.closed or self.render_timer then
    return
  end
  self.render_timer = U.later(self.opts.performance.render_ms, function()
    self.render_timer = nil
    if not self.closed then
      local ok, err = xpcall(function()
        self.ui:render()
      end, debug.traceback)
      if not ok then
        self:close()
        vim.notify(err, vim.log.levels.ERROR)
      end
    end
  end)
end
function Session:move(delta)
  if #self.results == 0 then
    return
  end
  self.index = (self.index - 1 + delta) % #self.results + 1
  self.current_id = self.results[self.index].id
  self:draw()
  require("xue-picker.preview").update(self)
end
function Session:get_selection()
  local result = {}
  for _, item in ipairs(self.items) do
    if self.selected[item.id] then
      result[#result + 1] = item
    end
  end
  if #result == 0 and self.results[self.index] then
    result[1] = self.results[self.index]
  end
  return result
end
function Session:rank()
  cancel(self, "cancel_match")
  self.match_generation = self.match_generation + 1
  local gen, query = self.match_generation, self.query
  self.searching = true
  self:draw()
  self.cancel_match = U.work(function(checkpoint)
    local result
    if self.opts.input then
      return self.items
    end
    if type(self.opts.matcher) == "function" then
      return self.opts.matcher(query, self.items, checkpoint)
    end
    if self.opts.live then
      result = self.items
    else
      result = self.ranker:rank(query, self.items, checkpoint)
    end
    if self.opts.sort == false and not self.opts.live then
      local ids, ordered = {}, {}
      for _, item in ipairs(result) do
        ids[item.id] = true
        checkpoint()
      end
      for _, item in ipairs(self.items) do
        if ids[item.id] then
          ordered[#ordered + 1] = item
        end
        checkpoint()
      end
      result = ordered
    end
    if self.opts.group then
      local paths, buckets, grouped = {}, {}, {}
      for _, item in ipairs(result) do
        local path = item.path or ""
        if not buckets[path] then
          buckets[path] = {}
          paths[#paths + 1] = path
        end
        buckets[path][#buckets[path] + 1] = item
        checkpoint()
      end
      U.sort(paths, function(a, b)
        return a < b
      end, checkpoint)
      for _, path in ipairs(paths) do
        for _, item in ipairs(buckets[path]) do
          grouped[#grouped + 1] = item
          checkpoint()
        end
      end
      result = grouped
    end
    return result
  end, function(result, err)
    if self.closed or gen ~= self.match_generation then
      return
    end
    self.searching = false
    if err then
      self.error = err
      self:draw()
      return
    end
    self.results = result or {}
    if self.opts.name == "files" and self.query == "" and self.cache_key and not self.opts.filter.fn then
      local cache = require("xue-picker.sources.files").cache[self.cache_key]
      if cache then
        cache.seed = vim.list_slice(self.results, 1, 64)
      end
    end
    self.index = math.max(1, math.min(self.index, #self.results))
    if self.current_id then
      for i, item in ipairs(self.results) do
        if item.id == self.current_id then
          self.index = i
          break
        end
      end
    end
    if self.results[self.index] then
      self.current_id = self.results[self.index].id
    end
    self:draw()
    require("xue-picker.preview").update(self)
    if self.opts.on_update then
      self.opts.on_update(self)
    end
  end, self.opts.performance.slice_ms)
end
function Session:receive(batch, state, generation)
  if self.closed or generation ~= self.source_generation then
    return
  end
  state = state or {}
  self.cache_key = state.cache_key or self.cache_key
  if
    state.seed
    and self.opts.name == "files"
    and self.query == ""
    and #self.results == 0
    and not self.opts.filter.fn
  then
    self.results, self.items = state.seed, batch
    U.stop(self.render_timer)
    self.render_timer = nil
    self.ui:render()
  end
  -- Queue source deliveries to prevent a late preparation from replacing newer data.
  self.deliveries[#self.deliveries + 1] = { batch or {}, state }
  if self.preparing then
    return
  end
  self.preparing = true
  self.cancel_prepare = U.work(function(checkpoint)
    while #self.deliveries > 0 do
      local delivery = table.remove(self.deliveries, 1)
      local values, info = delivery[1], delivery[2]
      if info.replace then
        self.items, self.ids = {}, {}
      end
      for _, value in ipairs(values) do
        local item = type(value) == "table" and value or { text = tostring(value), value = value }
        item.text = tostring(item.text or item.label or item.path or "")
        if item.path and item._prepared_cwd ~= self.opts.cwd then
          item.path = U.path(item.path, self.opts.cwd)
          item.file = item.file or item.path
        end
        item.id = item.id or item.path or tostring(#self.items + 1)
        item.idx = item.idx or #self.items + 1
        local include = not self.ids[item.id]
        if include and self.opts.filter.cwd and item.path then
          include = U.inside(item.path, self.opts.cwd)
        end
        if include and self.opts.filter.fn then
          include = self.opts.filter.fn(item, self)
        end
        if include then
          self.items[#self.items + 1] = item
          self.ids[item.id] = item
        end
        checkpoint()
      end
      if info.done then
        self.loading = false
      end
      if info.loading ~= nil then
        self.loading = info.loading
      end
      if info.replace or info.done then
        self.error = info.error
      end
      if info.truncated ~= nil then
        self.truncated = info.truncated
      end
      self.backend, self.fallback = info.backend or self.backend, info.fallback or self.fallback
    end
  end, function(_, err)
    if self.closed or generation ~= self.source_generation then
      return
    end
    self.preparing = false
    if err then
      self.error, self.loading = err, false
    end
    self:rank()
  end, self.opts.performance.slice_ms)
end
function Session:refresh()
  if self.closed then
    return
  end
  U.stop(self.query_timer)
  self.query_timer = nil
  cancel(self, "cancel_source")
  cancel(self, "cancel_prepare")
  cancel(self, "cancel_match")
  self.source_generation = self.source_generation + 1
  self.match_generation = self.match_generation + 1
  local gen = self.source_generation
  self.deliveries, self.preparing = {}, false
  self.loading, self.error, self.truncated = true, nil, false
  self:draw()
  local function emit(items, state)
    if vim.in_fast_event() then
      vim.schedule(function()
        self:receive(items, state, gen)
      end)
    else
      self:receive(items, state, gen)
    end
  end
  if self.opts.source then
    local ok, result = xpcall(function()
      return self.opts.source(
        { query = self.query, cwd = self.opts.cwd, session = self, generation = gen },
        emit
      )
    end, debug.traceback)
    if ok then
      self.cancel_source = type(result) == "function" and result or nil
    else
      emit({}, { error = result, done = true, replace = true })
    end
  else
    emit(self.opts.items or {}, { replace = true, done = true })
  end
end
function Session:set_query(query, from_input)
  if self.closed then
    return
  end
  query = tostring(query or ""):gsub("[\r\n]", " ")
  if not from_input then
    self.ui:query(query)
  end
  if query == self.query and self.started then
    return
  end
  self.query, self.current_id, self.index, self.offset = query, nil, 1, 1
  if self.opts.live then
    cancel(self, "cancel_source")
    cancel(self, "cancel_prepare")
    cancel(self, "cancel_match")
    self.source_generation = self.source_generation + 1
    self.match_generation = self.match_generation + 1
    self.deliveries, self.preparing = {}, false
    self.items, self.results, self.ids = {}, {}, {}
    self.loading, self.error, self.truncated = query ~= "", nil, false
    U.stop(self.query_timer)
    self.query_timer = U.later(self.opts.debounce_ms or 0, function()
      self:refresh()
    end)
    self:draw()
  else
    self:rank()
  end
end
function Session:accept(action)
  local selected = self:get_selection()
  if not self.opts.input and #selected == 0 then
    return
  end
  if self.opts.input then
    selected = { { text = self.query } }
  end
  if self.opts.on_accept then
    self.accepted = true
    self:close()
    self.opts.on_accept(selected, action, self)
  else
    local location = self.ranker and self.ranker:location(self.query)
    self.accepted = true
    self:close()
    require("xue-picker.actions").open(selected, action, location)
  end
end
function Session:act(name)
  if self.closed then
    return
  end
  local ok, err = xpcall(function()
    self.actions[name](self)
  end, debug.traceback)
  if not ok then
    if self.closed then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    else
      self.error = tostring(err)
      self:draw()
    end
  end
end
function Session:close()
  if self.closed then
    return
  end
  self.closed = true
  cancel(self, "cancel_source")
  cancel(self, "cancel_prepare")
  cancel(self, "cancel_match")
  cancel(self, "cancel_git")
  U.stop(self.query_timer)
  U.stop(self.render_timer)
  require("xue-picker.preview").cancel(self)
  if self.augroup then
    pcall(api.nvim_del_augroup_by_id, self.augroup)
  end
  if self.ui then
    self.ui:close()
  end
  if api.nvim_get_current_tabpage() == self.origin.tab and api.nvim_win_is_valid(self.origin.win) then
    api.nvim_set_current_win(self.origin.win)
    pcall(vim.fn.winrestview, self.origin.view)
  end
  vim.cmd("stopinsert")
  if M.active == self then
    M.active = nil
  end
  if self.opts.resumable ~= false then
    M.previous = {
      opts = self.opts,
      query = self.query,
      selected = vim.deepcopy(self.selected),
      current_id = self.current_id,
      index = self.index,
      preview = self.preview_enabled,
      seed = vim.list_slice(self.results, math.max(1, self.index - 8), self.index + 32),
      seed_index = math.min(self.index, 9),
    }
  end
  if self.opts.on_close then
    self.opts.on_close(self)
  end
end
function M.new(opts, restore)
  local actions = {
    next = function(s)
      s:move(1)
    end,
    previous = function(s)
      s:move(-1)
    end,
    accept = function(s)
      s:accept("edit")
    end,
    close = function(s)
      s:close()
    end,
    refresh = function(s)
      s:refresh()
    end,
  }
  if opts.file_actions then
    for _, action in ipairs({ "split", "vsplit", "tab" }) do
      actions[action] = function(s)
        s:accept(action)
      end
    end
  end
  if opts.file_actions or opts.preview_item then
    actions.preview = function(s)
      s.preview_enabled = not s.preview_enabled
      s.ui:layout()
      s:draw()
      require("xue-picker.preview").update(s)
    end
  end
  if opts.multiselect then
    actions.toggle = function(s)
      local item = s.results[s.index]
      if item then
        s.selected[item.id] = not s.selected[item.id] or nil
        s:draw()
      end
    end
    actions.toggle_all = function(s)
      local all = #s.results > 0
      for _, item in ipairs(s.results) do
        if not s.selected[item.id] then
          all = false
          break
        end
      end
      for _, item in ipairs(s.results) do
        s.selected[item.id] = not all or nil
      end
      s:draw()
    end
  end
  for name, action in pairs(opts.actions) do
    assert(type(action) == "function", "actions." .. name .. " 必须是函数")
    actions[name] = action
  end
  local keys = require("xue-picker.config").bindings(opts, actions)
  local core, err = require("xue-picker.ui").capability()
  assert(core, err)
  if M.active then
    M.active:close()
  end
  serial = serial + 1
  local self = setmetatable({
    opts = opts,
    actions = actions,
    keys = keys,
    items = {},
    results = restore and restore.seed or {},
    ids = {},
    selected = restore and restore.selected or {},
    index = restore and restore.seed_index or 1,
    offset = 1,
    current_id = restore and restore.current_id or nil,
    query = restore and restore.query or opts.query or "",
    preview_enabled = restore and restore.preview or opts.preview.enabled,
    git_status = {},
    source_generation = 0,
    match_generation = 0,
    deliveries = {},
    loading = true,
    origin = {
      win = api.nvim_get_current_win(),
      tab = api.nvim_get_current_tabpage(),
      buf = api.nvim_get_current_buf(),
      alternate = vim.fn.bufnr("#"),
      view = vim.fn.winsaveview(),
    },
  }, Session)
  M.active = self
  local ok, failure = xpcall(function()
    self.ui = require("xue-picker.ui").open(self)
    self.ui:query(self.query)
    self.ui:render()
    self.augroup = api.nvim_create_augroup("XuePickerSession" .. serial, { clear = true })
    api.nvim_create_autocmd({ "TabLeave", "VimLeavePre" }, {
      group = self.augroup,
      callback = function()
        self:close()
      end,
    })
    api.nvim_create_autocmd("CmdlineEnter", {
      group = self.augroup,
      callback = function()
        self:close()
      end,
    })
    api.nvim_create_autocmd("WinClosed", {
      group = self.augroup,
      callback = function(ev)
        if tonumber(ev.match) == self.ui.wins.input then
          self:close()
        end
      end,
    })
    api.nvim_create_autocmd("BufWipeout", {
      group = self.augroup,
      buffer = self.input_buf,
      callback = function()
        self:close()
      end,
    })
    api.nvim_create_autocmd("VimResized", {
      group = self.augroup,
      callback = function()
        self.ui:layout()
        self:draw()
      end,
    })
    api.nvim_create_autocmd("ColorScheme", {
      group = self.augroup,
      callback = function()
        self.ui.highlights(opts)
        self:draw()
      end,
    })
    vim.cmd("startinsert!")
    -- The input is already present; dependency loading and data preparation start next turn.
    vim.schedule(function()
      if self.closed then
        return
      end
      local initialized, problem = xpcall(function()
        local matcher_opts = type(opts.matcher) == "table"
            and require("xue-picker.config").merge(opts.matcher, { cwd = opts.cwd })
          or {}
        matcher_opts.git_modified_bonus = opts.git.modified_bonus
        if matcher_opts.frecency == true then
          matcher_opts.frecency = require("xue-picker.frecency").default(opts.frecency)
        end
        self.ranker = require("xue-picker.matcher").new(matcher_opts)
        if
          opts.icons == "auto"
          and not package.loaded["mini.icons"]
          and not package.loaded["nvim-web-devicons"]
        then
          local icons = pcall(require, "mini.icons")
          if not icons then
            pcall(require, "nvim-web-devicons")
          end
        end
        if opts.on_start then
          opts.on_start(self)
        end
        self.started = true
        self:refresh()
        if opts.file_actions and opts.git.enabled then
          self.cancel_git = require("xue-picker.sources.files").git(opts, function(statuses)
            if not self.closed then
              self.git_status = statuses
              if opts.git.modified_bonus then
                self.ranker.git_status = statuses
                self.ranker.bonuses = setmetatable({}, { __mode = "k" })
                self:rank()
              else
                self:draw()
              end
            end
          end)
        end
      end, debug.traceback)
      if not initialized then
        self.error, self.loading = problem, false
        self:draw()
      end
    end)
  end, debug.traceback)
  if not ok then
    self:close()
    error(failure)
  end
  return self
end
return M
