-- Independent implementation of the observable new_snacks contract at 241e22c.
-- Scores use fzf's published 16/-3/-1 match/gap constants and boundary bonuses.
local M = {}
local Ranker = {}
Ranker.__index = Ranker
local class = {}
for b = 0, 255 do
  local c = string.char(b)
  class[b] = c:match("%s") and 0
    or c:match("[/\\,:;|]") and 2
    or b >= 48 and b <= 57 and 6
    or b >= 65 and b <= 90 and 4
    or b >= 97 and b <= 122 and 3
    or 1
end
local function bonus(prev, cur, history)
  if cur > 1 and prev <= 2 then
    return prev == 0 and (history and 8 or 10) or prev == 2 and (history and 8 or 9) or 8
  end
  if prev == 3 and cur == 4 or prev ~= 6 and cur == 6 then
    return 7
  end
  return (cur == 1 or cur == 2) and 8 or cur == 0 and 10 or 0
end
local function score_run(text, first, last, opts, file, lookup, pattern)
  local value, run, initial, previous = 0, 0, 0, nil
  local sep = opts.path_separator or package.config:sub(1, 1)
  if
    file
    and opts.filename_bonus ~= false
    and not text:find(sep, first + 1, true)
    and not (sep ~= "/" and text:find("/", first + 1, true))
  then
    value = 6
  end
  local pos, index = first, 1
  while pos do
    local gap = previous and pos - previous - 1 or 0
    local p = gap == 0 and previous or pos - 1
    local b = bonus(class[text:byte(p)] or 0, class[text:byte(pos)] or 1, opts.history_bonus)
    if gap > 0 then
      value = value - 3 - (gap - 1)
      run, initial = 0, 0
    else
      if run == 0 then
        initial = b
      else
        if b >= 8 and b > initial then
          initial = b
        end
        b = math.max(b, initial, 4)
      end
      run = run + 1
    end
    value = value + 16 + b * (previous and 1 or 2)
    previous = pos
    if pattern then
      index = index + 1
      if index > #pattern then
        break
      end
      pos = lookup:find(pattern:sub(index, index), pos + 1, true)
      if not pos then
        return nil
      end
    else
      pos = pos + 1
      if pos > last then
        break
      end
    end
  end
  return value
end
local function term(opts, text)
  local t = { pattern = text, fuzzy = opts.fuzzy ~= false, entropy = opts.fuzzy == false and 10 or 0 }
  for _, p in ipairs({
    "^(.*[/\\].*):(%d*):(%d*)$",
    "^(.*[/\\].*):(%d*)$",
    "^(.+%.[a-z_]+):(%d*):(%d*)$",
    "^(.+%.[a-z_]+):(%d*)$",
  }) do
    local file, row, col = t.pattern:match(p)
    if file then
      t.field, t.pattern, t.location = "file", file .. "$", { tonumber(row), tonumber(col) }
      break
    end
  end
  local field, pattern = t.pattern:match("^([%w_][%w_]+):(.*)$")
  if field then
    t.field, t.pattern = field, pattern
  end
  if t.pattern:sub(1, 1) == "!" then
    t.inverse, t.fuzzy, t.pattern, t.entropy = true, false, t.pattern:sub(2), t.entropy - 1
  end
  if t.pattern:sub(1, 1) == "'" then
    t.fuzzy, t.pattern, t.entropy = false, t.pattern:sub(2), t.entropy + 10
    if t.pattern:sub(-1) == "'" then
      t.word, t.pattern, t.entropy = true, t.pattern:sub(1, -2), t.entropy + 10
    end
  elseif t.pattern:sub(1, 1) == "^" then
    t.prefix, t.fuzzy, t.pattern, t.entropy = true, false, t.pattern:sub(2), t.entropy + 20
  end
  if t.pattern:sub(-1) == "$" then
    t.suffix, t.fuzzy, t.pattern, t.entropy = true, false, t.pattern:sub(1, -2), t.entropy + 20
  end
  local lower = t.pattern:lower() == t.pattern
  t.ignorecase = opts.ignorecase ~= false
  if opts.smartcase ~= false then
    t.ignorecase = lower
  end
  t.entropy = t.entropy + math.min(#t.pattern, 20) + 2 * #t.pattern:gsub("[%w%s]", "")
  if not t.ignorecase and not lower then
    t.entropy = t.entropy * 2
  end
  if t.ignorecase then
    t.pattern = t.pattern:lower()
  end
  return t
end
function Ranker:parse(query)
  if query == self.query then
    return self.groups
  end
  local groups, is_or = {}, false
  for part in query:gmatch("[^ ]+") do
    if part == "|" then
      is_or = true
    else
      local t = term(self.opts, part)
      if t.pattern ~= "" then
        if is_or and #groups > 0 then
          table.insert(groups[#groups], t)
        else
          groups[#groups + 1] = { t }
        end
      end
      is_or = false
    end
  end
  for _, group in ipairs(groups) do
    table.sort(group, function(a, b)
      return a.entropy < b.entropy
    end)
  end
  table.sort(groups, function(a, b)
    return a[1].entropy > b[1].entropy
  end)
  self.query, self.groups = query, groups
  return groups
end
function Ranker:match(item, t, want_positions)
  local field = t.field or "text"
  local text = field == "file" and (item.file or item.path) or item[field]
  if text == nil then
    return t.inverse and 1000 or nil
  end
  text = tostring(text)
  local lookup = text
  if t.ignorecase then
    local cache = self.lower[item]
    if not cache then
      cache = {}
      self.lower[item] = cache
    end
    if not cache[field] or cache[field][1] ~= text then
      cache[field] = { text, text:lower() }
    end
    lookup = cache[field][2]
  end
  local best, best_first, best_last
  local pat = t.pattern
  if t.fuzzy then
    if not lookup:find(pat:sub(-1), 1, true) then
      return nil
    end
    local start = lookup:find(pat:sub(1, 1), 1, true)
    while start do
      local score = score_run(text, start, nil, self.opts, item.path or item.file, lookup, pat)
      if not score then
        break
      end
      if not best or score > best then
        best, best_first = score, start
      end
      start = lookup:find(pat:sub(1, 1), start + 1, true)
    end
  else
    local first, last
    if t.prefix then
      if lookup:sub(1, #pat) == pat then
        first, last = 1, #pat
      end
    elseif t.suffix then
      if lookup:sub(-#pat) == pat then
        first, last = #lookup - #pat + 1, #lookup
      end
    else
      first, last = lookup:find(pat, 1, true)
      while t.word and first do
        if
          (first == 1 or class[lookup:byte(first - 1)] < 3)
          and (last == #lookup or class[lookup:byte(last + 1)] < 3)
        then
          break
        end
        first, last = lookup:find(pat, last + 1, true)
      end
    end
    if t.inverse then
      return not first and 1000 or nil
    end
    if first then
      best = score_run(text, first, last, self.opts, item.path or item.file)
      best_first, best_last = first, last
    end
  end
  local positions
  if want_positions and best_first then
    positions = { best_first }
    if t.fuzzy then
      for i = 2, #pat do
        positions[i] = lookup:find(pat:sub(i, i), positions[i - 1] + 1, true)
      end
    else
      for p = best_first + 1, best_last do
        positions[#positions + 1] = p
      end
    end
  end
  return best, positions, text
end
function Ranker:bonus(item)
  if self.bonuses[item] ~= nil then
    return self.bonuses[item]
  end
  local value = 0
  if
    self.opts.cwd_bonus ~= false
    and item.path
    and self.opts.cwd
    and require("xue-picker.util").inside(item.path, self.opts.cwd)
  then
    value = 10
  end
  if self.frecency and item.path then
    local freq = self.frecency:get(item, { normalized = true })
    value = value + 8 * (1 - 1 / (1 + freq))
  end
  if self.opts.git_modified_bonus and item.path and self.git_status and self.git_status[item.path] then
    value = value + (type(self.opts.git_modified_bonus) == "number" and self.opts.git_modified_bonus or 20)
  end
  self.bonuses[item] = value
  return value
end
function Ranker:rank(query, candidates, checkpoint)
  checkpoint = checkpoint or function() end
  query = vim.trim(query or "")
  local old = self.completed_query
  local groups = self:parse(query)
  if self.ordered_source ~= candidates or self.ordered_count ~= #candidates then
    local lengths, buckets, ordered = {}, {}, {}
    for i, item in ipairs(candidates) do
      item.idx = item.idx or i
      local length = #item.text
      if not buckets[length] then
        buckets[length] = {}
        lengths[#lengths + 1] = length
      end
      local b = buckets[length]
      b[#b + 1] = item
      if i % 128 == 0 then
        checkpoint()
      end
    end
    require("xue-picker.util").sort(lengths, function(a, b)
      return a < b
    end, checkpoint)
    for _, length in ipairs(lengths) do
      local b, sorted = buckets[length], true
      for i = 2, #b do
        if b[i - 1].idx > b[i].idx then
          sorted = false
          break
        end
        if i % 128 == 0 then
          checkpoint()
        end
      end
      if not sorted then
        require("xue-picker.util").sort(b, function(a, z)
          return a.idx < z.idx
        end, checkpoint)
      end
      for _, item in ipairs(b) do
        ordered[#ordered + 1] = item
        if #ordered % 128 == 0 then
          checkpoint()
        end
      end
    end
    self.ordered_source, self.ordered_count, self.ordered = candidates, #candidates, ordered
  end
  local source = self.ordered
  if
    self.source == candidates
    and self.count == #candidates
    and old
    and old ~= ""
    and query:sub(1, #old) == old
    and not query:find("[^%s%w]")
  then
    source = self.matched
  end
  local buckets, scores, matched = {}, {}, {}
  for i, item in ipairs(source) do
    item.idx = item.idx or i
    local total = #groups == 0 and 1000 or 0
    for _, group in ipairs(groups) do
      local value
      for _, t in ipairs(group) do
        value = self:match(item, t)
        if value then
          break
        end
      end
      if not value then
        total = nil
        break
      end
      total = total + value
    end
    item.score = total
    if total and total ~= 0 then
      total = total + self:bonus(item)
      item.score = total > 0 and total or nil
      if total > 0 then
        matched[#matched + 1] = item
        if not buckets[total] then
          buckets[total] = {}
          scores[#scores + 1] = total
        end
        local b = buckets[total]
        b[#b + 1] = item
      end
    end
    if i % 64 == 0 then
      checkpoint()
    end
  end
  require("xue-picker.util").sort(scores, function(a, b)
    return a > b
  end, checkpoint)
  local ranked = {}
  for _, s in ipairs(scores) do
    for _, item in ipairs(buckets[s]) do
      ranked[#ranked + 1] = item
      if #ranked % 128 == 0 then
        checkpoint()
      end
    end
    checkpoint()
  end
  self.source, self.count, self.matched, self.completed_query = candidates, #candidates, matched, query
  return ranked
end
function Ranker:positions(query, item)
  local bytes = self:byte_positions(query, item)
  local out, offset = {}, 1
  for i, char in ipairs(vim.fn.split(item.text, "\\zs")) do
    for b = offset, offset + #char - 1 do
      if bytes[b - 1] then
        out[i - 1] = true
        break
      end
    end
    offset = offset + #char
  end
  return out
end
function Ranker:byte_positions(query, item)
  local out = {}
  for _, group in ipairs(self:parse(vim.trim(query or ""))) do
    for _, t in ipairs(group) do
      if not t.field or t.field == "file" or t.field == "text" then
        local _, positions, text = self:match(item, t, true)
        if positions and text:sub(-#item.text) == item.text then
          local offset = #text - #item.text
          for _, p in ipairs(positions) do
            if p > offset then
              out[p - offset - 1] = true
            end
          end
        end
      end
    end
  end
  return out
end
function Ranker:location(query)
  for _, group in ipairs(self:parse(vim.trim(query or ""))) do
    for _, t in ipairs(group) do
      if t.location then
        return t.location
      end
    end
  end
end
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    opts = opts,
    lower = setmetatable({}, { __mode = "k" }),
    bonuses = setmetatable({}, { __mode = "k" }),
    frecency = type(opts.frecency) == "table" and opts.frecency or nil,
  }, Ranker)
end
M.new_snacks = M.new
return M
