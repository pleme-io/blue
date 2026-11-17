# Equality on numbers: == and != answer the same on every evaluator, whether
# the pair runs in place (two Ints, two Floats) or through blue's structural
# equality (any other pair).

row(
  "equality.numbers.ints_and_floats",
  "[1 == 1, 1 == 2, 1.5 == 1.5, 4 == 4.0, 4.0 == 4, 1 != 1, 1 != 2, 2.5 != 2.5, 4 != 4.0]",
  value("[true, false, true, true, true, false, true, false, false]")
)

row(
  "equality.numbers.signed_zero",
  "[0.0 == -0.0, 0.0 != -0.0, 0 == -0.0]",
  value("[true, false, true]")
)

row(
  "equality.numbers.extremes",
  "[9223372036854775807 == 9223372036854775807, -9223372036854775807 != 9223372036854775807]",
  value("[true, true]")
)

row(
  "equality.numbers.in_a_loop",
  join_lines(
    [
      "def count(i, acc)",
      "  if i == 0",
      "    acc",
      "  elsif i != 3",
      "    count(i - 1, acc + 1)",
      "  else",
      "    count(i - 1, acc)",
      "  end",
      "end",
      "",
      "count(10, 0)"
    ]
  ),
  value("9")
)

row(
  "equality.mixed.other_kinds_stay_structural",
  "[\"a\" == \"a\", :k == :k, nil == nil, [1] == [1.0], 1 == \"1\", nil != false]",
  value("[true, true, true, true, false, true]")
)
