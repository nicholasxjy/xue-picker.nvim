local U, api = require("xue-picker.util"), vim.api
local M = {}
M.names = {
  "files",
  "smart",
  "buffers",
  "live_grep",
  "grep_word",
  "diagnostics",
  "marks",
  "oldfiles",
  "git_files",
  "history",
  "manpages",
}
local function launch(name, opts, build)
  opts = require("xue-picker.config").resolve(name, opts)
  opts.name, opts.cwd = name, U.cwd(opts.cwd)
  if name ~= "history" and name ~= "manpages" then
    opts.file_actions, opts.multiselect = true, true
  end
  build(opts)
  return require("xue-picker.session").new(opts)
end
local function recent(opts, callback)
  local paths, items, seen = vim.deepcopy(vim.v.oldfiles), {}, {}
  local cancelled, index = false, 1
  local function next_path()
    if cancelled then
      return
    end
    local path = paths[index]
    index = index + 1
    if not path then
      callback(items)
      return
    end
    path = U.path(path)
    if not path or seen[path] or opts.filter.cwd and not U.inside(path, opts.cwd) then
      vim.schedule(next_path)
      return
    end
    seen[path] = true
    vim.uv.fs_stat(
      path,
      vim.schedule_wrap(function(_, stat)
        if cancelled then
          return
        end
        if stat and stat.type == "file" then
          local item = U.file(path, opts.cwd)
          item.recent, item.lastused = true, stat.mtime.sec
          items[#items + 1] = item
        end
        next_path()
      end)
    )
  end
  next_path()
  return function()
    cancelled = true
  end
end
function M.files(opts)
  return launch("files", opts, function(o)
    o.source = o.source
      or function(_, emit)
        return require("xue-picker.sources.files").scan(o, emit)
      end
  end)
end
function M.smart(opts)
  return launch("smart", opts, function(o)
    o.live, o.matcher = true, false
    o.source = o.source
      or function(ctx, emit)
        return require("xue-picker.sources.fff").search(o, ctx, emit)
      end
  end)
end
function M.buffers(opts)
  return launch("buffers", opts, function(o)
    o.source = o.source
      or function(ctx, emit)
        require("xue-picker.buffers").source(ctx, emit, o)
      end
    if not o.actions.delete then
      o.actions.delete = function(s)
        local failed = {}
        for _, item in ipairs(s:get_selection()) do
          if api.nvim_buf_is_valid(item.bufnr) then
            if vim.bo[item.bufnr].modified and not o.force then
              failed[#failed + 1] = item.text
            else
              api.nvim_buf_delete(item.bufnr, { force = o.force })
              s.selected[item.id] = nil
            end
          end
        end
        s:refresh()
        if #failed > 0 then
          vim.schedule(function()
            if not s.closed then
              s.error = "Kept buffers with unsaved changes: " .. table.concat(failed, ", ")
              s:draw()
            end
          end)
        end
      end
    end
  end)
end
function M.live_grep(opts)
  return launch("live_grep", opts, function(o)
    o.live, o.group = true, true
    o.source = o.source
      or function(ctx, emit)
        ctx.session.grep_search = ctx.session.grep_search or require("xue-picker.grep").new(o)
        return ctx.session.grep_search(ctx.query, emit)
      end
  end)
end
function M.grep_word(opts)
  local options = vim.tbl_extend("force", { mode = "plain" }, opts or {}, {
    query = vim.fn.expand("<cword>"),
  })
  return M.live_grep(options)
end
function M.diagnostics(opts)
  return launch("diagnostics", opts, function(o)
    o.source = o.source
      or function(ctx, emit)
        local buf = (o.scope == "buffer" or o.bufnr)
            and (o.bufnr == 0 and ctx.session.origin.buf or o.bufnr or ctx.session.origin.buf)
          or nil
        local values = vim.diagnostic.get(buf, { severity = o.severity })
        values = require("xue-picker.diagnostics").sort(values, o)
        local items = {}
        for i, d in ipairs(values) do
          local path = U.path(api.nvim_buf_get_name(d.bufnr))
          if o.scope ~= "cwd" or path and U.inside(path, o.cwd) then
            items[#items + 1] = {
              id = (path or "buffer:" .. d.bufnr) .. ":" .. d.lnum .. ":" .. d.col .. ":" .. i,
              path = path,
              file = path,
              bufnr = d.bufnr,
              lnum = d.lnum + 1,
              col = d.col,
              severity = d.severity,
              text = d.message,
              source = d.source,
              code = d.code,
            }
          end
        end
        emit(items, { replace = true, done = true })
      end
    local on_start = o.on_start
    o.on_start = function(s)
      if on_start then
        on_start(s)
      end
      api.nvim_create_autocmd("DiagnosticChanged", {
        group = s.augroup,
        callback = function()
          s:refresh()
        end,
      })
    end
  end)
end
function M.marks(opts)
  return launch("marks", opts, function(o)
    o.source = o.source
      or function(ctx, emit)
        local marks = vim.list_extend(vim.fn.getmarklist(), vim.fn.getmarklist(ctx.session.origin.buf))
        return U.work(function(checkpoint)
          local items, seen = {}, {}
          for _, mark in ipairs(marks) do
            local pos = mark.pos
            if pos[2] > 0 and not seen[mark.mark] then
              seen[mark.mark] = true
              local buf = pos[1] > 0 and pos[1] or ctx.session.origin.buf
              local path = mark.file and mark.file ~= "" and U.path(vim.fn.expand(mark.file))
                or U.path(api.nvim_buf_get_name(buf))
              local context = ""
              if api.nvim_buf_is_loaded(buf) then
                context = api.nvim_buf_get_lines(buf, pos[2] - 1, pos[2], false)[1] or ""
              elseif path then
                local ok, lines = pcall(vim.fn.readfile, path, "", pos[2])
                if ok then
                  context = lines[pos[2]] or ""
                end
              end
              items[#items + 1] = {
                id = mark.mark,
                path = path,
                file = path,
                bufnr = api.nvim_buf_is_loaded(buf) and buf or nil,
                lnum = pos[2],
                col = math.max(0, pos[3] - 1),
                text = mark.mark
                  .. "  "
                  .. (path and U.relative(path, o.cwd) or "[No Name]")
                  .. "  "
                  .. context,
              }
            end
            checkpoint()
          end
          return items
        end, function(items, err)
          emit(items or {}, { replace = true, done = true, error = err })
        end, o.performance.slice_ms)
      end
  end)
end
function M.oldfiles(opts)
  return launch("oldfiles", opts, function(o)
    o.source = o.source
      or function(_, emit)
        return recent(o, function(items)
          emit(items, { replace = true, done = true })
        end)
      end
  end)
end
function M.git_files(opts)
  return launch("git_files", opts, function(o)
    o.source = o.source
      or function(_, emit)
        local args = { "git", "ls-files", "-z", "--cached" }
        if o.untracked then
          vim.list_extend(args, { "--others", "--exclude-standard" })
        end
        local items = {}
        return require("xue-picker.process").stream(args, { cwd = o.cwd }, "\0", function(path)
          items[#items + 1] = U.file(path, o.cwd)
        end, function(err)
          emit(items, { replace = true, done = true, error = err })
        end)
      end
  end)
end
function M.history(opts)
  return launch("history", opts, function(o)
    assert(o.type == "cmd" or o.type == "search", "history.type must be cmd/search")
    o.source = o.source
      or function(_, emit)
        local items = {}
        for i = vim.fn.histnr(o.type), 1, -1 do
          local text = vim.fn.histget(o.type, i)
          if text ~= "" then
            items[#items + 1] = { id = tostring(i), text = text }
          end
        end
        emit(items, { replace = true, done = true })
      end
    o.on_accept = o.on_accept
      or function(items)
        local text = items[1].text
        if o.type == "cmd" then
          vim.schedule(function()
            -- setcmdline preserves even embedded newlines without executing history.
            api.nvim_create_autocmd("CmdlineEnter", {
              pattern = ":",
              once = true,
              callback = function()
                vim.schedule(function()
                  if vim.fn.getcmdtype() == ":" then
                    vim.fn.setcmdline(text)
                  end
                end)
              end,
            })
            api.nvim_feedkeys(":", "nt", true)
          end)
        else
          vim.fn.setreg("/", text)
          vim.fn.histadd("search", text)
          vim.fn.search(text, "")
          vim.cmd("normal! zv")
        end
      end
  end)
end
function M.manpages(opts)
  return launch("manpages", opts, function(o)
    o.source = o.source
      or function(_, emit)
        local items, seen = {}, {}
        return require("xue-picker.process").stream(
          o.cmd or { "man", "-k", "." },
          { cwd = o.cwd },
          "\n",
          function(line)
            local name, section = line:match("^([^%s,]+)%s*%(([^)]+)%)")
            if name then
              local id = name .. "(" .. section .. ")"
              if not seen[id] then
                seen[id] = true
                items[#items + 1] = { id = id, text = line, name = name, section = section }
              end
            end
          end,
          function(err)
            emit(items, { replace = true, done = true, error = err })
          end
        )
      end
    o.on_accept = o.on_accept
      or function(items)
        if vim.fn.exists(":Man") == 0 then
          vim.cmd("runtime plugin/man.lua")
        end
        vim.cmd({ cmd = "Man", args = { items[1].section, items[1].name } })
      end
  end)
end
local function once(callback)
  local called = false
  return function(...)
    if not called then
      called = true
      callback(...)
    end
  end
end
function M.ui_select(items, opts, on_choice)
  opts, items = opts or {}, items or {}
  local callback = once(on_choice or function() end)
  local choices = {}
  for i, item in ipairs(items) do
    choices[i] = {
      id = tostring(i),
      text = opts.format_item and opts.format_item(item) or tostring(item),
      value = item,
      original_index = i,
    }
  end
  local options = require("xue-picker.config").merge(opts, {
    name = "ui_select",
    items = choices,
    resumable = false,
    sort = false,
    prompt = opts.prompt and opts.prompt:gsub(":%s?$", "> ") or nil,
    on_accept = function(selected)
      callback(items[selected[1].original_index], selected[1].original_index)
    end,
    on_close = function(s)
      if not s.accepted then
        callback(nil, nil)
      end
    end,
  })
  local ok, result = pcall(require("xue-picker").pick, options)
  if not ok then
    callback(nil, nil)
    error(result)
  end
  return result
end
function M.ui_input(opts, on_confirm)
  opts = opts or {}
  local callback = once(on_confirm or function() end)
  local options = require("xue-picker.config").merge(opts, {
    name = "ui_input",
    resumable = false,
    input = true,
    live = opts.completion ~= nil,
    debounce_ms = 0,
    query = opts.default or "",
    on_accept = function(selected)
      callback(selected[1].text)
    end,
    on_close = function(s)
      if not s.accepted then
        callback(nil)
      end
    end,
  })
  if opts.completion then
    options.source = function(ctx, emit)
      local values
      local kind, fn = opts.completion:match("^(custom%a*),(.+)$")
      if kind then
        values = vim.fn[fn](ctx.query, ctx.query, #ctx.query)
        if type(values) == "string" then
          values = vim.split(values, "\n", { trimempty = true })
        end
      else
        values = vim.fn.getcompletion(ctx.query, opts.completion)
      end
      emit(values, { replace = true, done = true })
    end
    options.actions = require("xue-picker.config").merge({
      complete = function(s)
        local item = s.results[s.index]
        if item then
          s:set_query(item.text)
        end
      end,
    }, options.actions)
    local bindings = require("xue-picker.config").resolve("ui_input", opts).keymaps
    local next_keys = bindings.next
    if next_keys ~= false then
      next_keys = type(next_keys) == "string" and { next_keys } or next_keys
      bindings.next = vim.tbl_filter(function(key)
        return api.nvim_replace_termcodes(key, true, true, true) ~= "\t"
      end, next_keys)
    end
    bindings.complete = bindings.complete == nil and "<Tab>" or bindings.complete
    options.keymaps = bindings
  end
  local ok, result = pcall(require("xue-picker").pick, options)
  if not ok then
    callback(nil)
    error(result)
  end
  return result
end
return M
