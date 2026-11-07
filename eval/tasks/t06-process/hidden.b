test "eval t06: squares answers in the order of its input"
  assert squares([]) == []
  assert squares([3, 1, 2]) == [9, 1, 4]
  assert squares(range(20)) == map((x) -> x * x, range(20))
end

test "eval t06: the work is done by processes"
  src = read_file(getenv("EVAL_SUBMISSION"))
  assert contains?(src, "spawn(")
  assert contains?(src, "send(")
  assert contains?(src, "receive(")
end
