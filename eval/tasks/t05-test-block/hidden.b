def eval_t05_caught(src, from, to)
  dir = path_join(temp_dir("eval-t05"), "eval-t05")
  mkdir_p(dir)
  path = path_join(dir, "mutant.b")
  write_program(path, replace(src, unlines(from), unlines(to)))
  status = exec_capture(self_exe, "test", path)[0][1]
  rm_rf(dir)
  status != 0
end

test "eval t05: median is kept as given and has at least three tests"
  src = read_file(getenv("EVAL_SUBMISSION"))
  assert contains?(src, unlines(["    (s[h - 1] + s[h]) / 2"]))
  assert contains?(src, unlines(["    s[h]", "  else"]))
  assert contains?(src, unlines(["  if n == 0", "    nil"]))
  assert length(
    filter((l) -> starts_with?(l, "test \""), split(src, line_break))
  ) >= 3
end

test "eval t05: the tests fail on each wrong median"
  src = read_file(getenv("EVAL_SUBMISSION"))
  assert eval_t05_caught(src, ["    (s[h - 1] + s[h]) / 2"], ["    s[h]"])
  assert eval_t05_caught(src, ["    s[h]", "  else"], ["    s[0]", "  else"])
  assert eval_t05_caught(
    src,
    ["  if n == 0", "    nil"],
    ["  if n == 0", "    0"]
  )
end
