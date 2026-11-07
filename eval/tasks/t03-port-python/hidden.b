test "eval t03: run_length counts each run in order"
  assert run_length("") == []
  assert run_length("a") == [["a", 1]]
  assert run_length("aaab") == [["a", 3], ["b", 1]]
  assert run_length("abba") == [["a", 1], ["b", 2], ["a", 1]]
  assert run_length("zzzz") == [["z", 4]]
end
