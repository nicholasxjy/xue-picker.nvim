local M = {}

local function color(spans, offset, base)
  local group, priority = base or "XuePickerNormal", 0
  for _, mark in ipairs(spans) do
    if mark[1] <= offset and offset < mark[2] and (mark[4] or 150) >= priority then
      group, priority = mark[3], mark[4] or 150
    end
  end
  return group, priority > 0 and priority or nil
end

function M.clip(text, spans, width, base, uncolored)
  local limit = math.max(0, width - 1)
  if vim.fn.strdisplaywidth(text) <= limit then
    return text, spans
  end
  local dots = math.min(2, limit)
  local budget, bytes, columns, finish = limit - dots, 0, 0, 0
  for i = 0, vim.fn.strchars(text, true) - 1 do
    local char = vim.fn.strcharpart(text, i, 1, true)
    bytes, columns = bytes + #char, columns + vim.fn.strdisplaywidth(char)
    if columns > budget then
      break
    end
    finish = bytes
  end
  local clipped = {}
  for _, mark in ipairs(spans) do
    if mark[1] < finish then
      clipped[#clipped + 1] = { mark[1], math.min(mark[2], finish), mark[3], mark[4] }
    end
  end
  local prefix, offset = text:sub(1, finish), finish
  local next_char = text:sub(finish + 1):gmatch("[%z\1-\127\194-\244][\128-\191]*")
  for _ = 1, dots do
    -- fzf colors its ellipsis using the replaced characters, not their cell widths.
    local group, priority = color(spans, offset, offset < #text and (uncolored or "XuePickerNormal") or base)
    clipped[#clipped + 1] = { #prefix, #prefix + #"·", group, priority }
    prefix = prefix .. "·"
    offset = offset + #(next_char() or "")
  end
  return prefix, clipped
end

function M.scroll(text, spans, width, gutter, last_match, base)
  local prefix, body = text:sub(1, gutter), text:sub(gutter + 1)
  local available = width - 1 - vim.fn.strdisplaywidth(prefix)
  if available < 4 or not last_match or last_match <= gutter or vim.fn.strdisplaywidth(body) <= available then
    return M.clip(text, spans, width, base, base)
  end
  -- Match fzf's default horizontal context: up to ten characters after the
  -- final match, capped at half the viewport minus the ellipsis.
  local finish = vim.fn.strchars(body:sub(1, last_match - gutter))
    + math.min(10, math.floor(available / 2) - 2)
  local context = vim.fn.strcharpart(body, 0, finish)
  if vim.fn.strdisplaywidth(context) <= available - 2 then
    return M.clip(text, spans, width, base, base)
  end
  local body_spans, out = {}, {}
  for _, mark in ipairs(spans) do
    if mark[2] <= gutter then
      out[#out + 1] = mark
    else
      body_spans[#body_spans + 1] = { math.max(0, mark[1] - gutter), mark[2] - gutter, mark[3], mark[4] }
    end
  end
  if vim.fn.strdisplaywidth(body:sub(#context + 1)) > 2 then
    body, body_spans = M.clip(body, body_spans, vim.fn.strdisplaywidth(context) + 3, base, base)
  end
  local start, remaining = 0, vim.fn.strdisplaywidth(body)
  for i = 0, vim.fn.strchars(body, true) - 1 do
    if remaining <= available - 2 then
      break
    end
    local char = vim.fn.strcharpart(body, i, 1, true)
    start, remaining = start + #char, remaining - vim.fn.strdisplaywidth(char)
  end
  local removed = body:sub(1, start)
  local offset = #vim.fn.strcharpart(removed, 0, math.max(0, vim.fn.strchars(removed) - 2))
  local next_char = removed:sub(offset + 1):gmatch("[%z\1-\127\194-\244][\128-\191]*")
  for _ = 1, 2 do
    local group, priority = color(body_spans, offset, base)
    out[#out + 1] = { #prefix, #prefix + #"·", group, priority }
    prefix = prefix .. "·"
    offset = offset + #(next_char() or "")
  end
  for _, mark in ipairs(body_spans) do
    if mark[2] > start then
      out[#out + 1] = { #prefix + math.max(0, mark[1] - start), #prefix + mark[2] - start, mark[3], mark[4] }
    end
  end
  return prefix .. body:sub(start + 1), out
end

return M
