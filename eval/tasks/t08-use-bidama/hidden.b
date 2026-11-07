test "eval t08: longest_word measures words split on any whitespace"
  assert longest_word("a  bcd\tef") == 3
  assert longest_word(join_lines(["one", "two three"])) == 5
  assert longest_word("   ").nil?
  assert longest_word("").nil?
end

test "eval t08: the words come from bidamas brought in with use"
  src = read_file(getenv("EVAL_SUBMISSION"))
  assert contains?(src, "use(\"moji\", [:words])")
  assert contains?(src, "use(\"kazu\", [:max_of])")
end
