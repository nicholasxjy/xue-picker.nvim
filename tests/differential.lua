vim.opt.runtimepath:prepend(vim.fn.getcwd())
local reference = vim.env.XUE_REFERENCE or vim.fn.expand("~/code/minibuffer.nvim")
local commit = "241e22ccc870e47c78a07264ee7890d355e37102"
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/lua/minibuffer/fuzzy", "p")
for _, file in ipairs({ "init", "score", "frecency" }) do
  local result = vim
    .system({ "git", "-C", reference, "show", commit .. ":lua/minibuffer/fuzzy/" .. file .. ".lua" })
    :wait()
  assert(
    result.code == 0,
    "固定参考提交不可用，请设置 XUE_REFERENCE 为 minibuffer.nvim checkout"
  )
  vim.fn.writefile(
    vim.split(result.stdout, "\n", { plain = true }),
    temp .. "/lua/minibuffer/fuzzy/" .. file .. ".lua"
  )
end
vim.opt.runtimepath:append(temp)
local count = 0
local function eq(a, b, message)
  assert(vim.deep_equal(a, b), message .. "\nreference: " .. vim.inspect(a) .. "\nactual: " .. vim.inspect(b))
  count = count + 1
end
local function compare(opts, queries, candidates)
  local expected = require("minibuffer.fuzzy").new_snacks(opts)
  local actual = require("xue-picker.matcher").new(opts)
  local left, right = vim.deepcopy(candidates), vim.deepcopy(candidates)
  for _, query in ipairs(queries) do
    local a, b = expected:rank(query, left), actual:rank(query, right)
    local function compact(items)
      return vim.tbl_map(function(item)
        return { item.text, item.idx, item.score }
      end, items)
    end
    eq(compact(a), compact(b), "rank " .. query .. " " .. vim.inspect(opts))
    for i, item in ipairs(a) do
      eq(
        expected:positions(query, item),
        actual:positions(query, b[i]),
        "positions " .. query .. ":" .. item.text
      )
    end
  end
end
local texts = {
  "foo.lua",
  "src/foo.lua",
  "foo/src.lua",
  "fooBar.lua",
  "foobar",
  "aabba",
  "a_bc",
  "foo bar",
  "src/bar.lua",
  "test/foo.lua",
  "a/foo.lua",
  "b/foo.lua",
  "src\\foo.lua",
  "文件/你好.lua",
  "café.lua",
  "CAFÉ.lua",
  "emoji/🍵你好.txt",
  "dup",
  "dup",
  "file with space.lua",
  "a\tfoo.lua",
  "dir/foo/bar/aBC123.lua",
}
local candidates = {}
for i, text in ipairs(texts) do
  candidates[i] = { text = text, path = "/repo/" .. text, file = "/repo/" .. text, idx = i, kind = "lua" }
end
local queries = {
  "",
  "f",
  "fo",
  "foo",
  "f",
  "FO",
  "fb",
  "FB",
  "aba",
  "abc",
  "^foo",
  "bar$",
  "'foo",
  "'foo'",
  "!test foo",
  "foo | bar",
  "foo bar",
  "!zzz | foo",
  "file:lua$",
  "kind:lua",
  "missing:!hi",
  "foo.lua:10",
  "foo.lua:10:3",
  "^foo$",
  "!^foo",
  "!bar$",
  "'foo$",
  "!",
  "'",
  "^",
  "$",
  " | ",
  "你好",
  "文",
  "café",
  "CAFÉ",
  "🍵",
  "abc123",
  "foo\tbar",
}
for _, opts in ipairs({
  { cwd = "/repo", frecency = false },
  { filename_bonus = false, cwd_bonus = false, frecency = false },
  { cwd = "/outside", smartcase = false, ignorecase = false, history_bonus = true, frecency = false },
  { cwd = "/repo", path_separator = "\\", fuzzy = false, frecency = false },
  { cwd = "/repo", frecency = {
    get = function(_, item)
      return item.idx % 7
    end,
  } },
}) do
  compare(opts, queries, candidates)
end
math.randomseed(24122)
local alphabet = "aAbB12_-/é"
local random = {}
for i = 1, 400 do
  local text = ""
  for _ = 1, math.random(3, 30) do
    local p = math.random(1, 9)
    text = text .. alphabet:sub(p, p)
  end
  random[i] = { text = text, path = "/repo/" .. text, idx = 401 - i }
end
local q = {}
for _ = 1, 100 do
  local text = ""
  for _ = 1, math.random(1, 4) do
    local p = math.random(1, 9)
    text = text .. alphabet:sub(p, p)
  end
  q[#q + 1] = text
end
compare({ cwd = "/repo", frecency = false }, q, random)
local ref = require("minibuffer.fuzzy.frecency").new({
  data = {},
  now = function()
    return 1700000000
  end,
})
local own = require("xue-picker.frecency").new({
  data = {},
  now = function()
    return 1700000000
  end,
})
for _, item in ipairs(candidates) do
  ref:visit(item, 3)
  own:visit(item, 3)
  eq(ref:get(item), own:get(item), "frecency " .. item.text)
end
vim.fn.delete(temp, "rf")
print(("Differential: %d assertions, reference %s"):format(count, commit))
