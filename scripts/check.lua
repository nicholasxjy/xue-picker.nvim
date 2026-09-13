for _, directory in ipairs({ "lua", "plugin", "tests", "scripts" }) do
  for path, kind in vim.fs.dir(directory, { depth = math.huge }) do
    if kind == "file" and path:match("%.lua$") then
      assert(loadfile(directory .. "/" .. path))
    end
  end
end
print("Lua syntax OK")
