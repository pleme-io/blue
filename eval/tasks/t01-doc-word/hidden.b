test "eval t01: clamp holds a value inside, below and above the range"
  assert clamp(2, 0, 3) == 2
  assert clamp(-1, 0, 3) == 0
  assert clamp(9, 0, 3) == 3
  assert clamp(0, 0, 0) == 0
end

test "eval t01: clamp carries a doc that starts with its name and an example"
  src = read_file(getenv("EVAL_SUBMISSION"))
  assert contains?(src, join_lines(["@doc \"\"\"", "clamp"]))
  assert contains?(src, " #=> ")
end
