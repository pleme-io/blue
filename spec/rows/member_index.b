# A membership test in a loop over a list the loop cannot change is answered
# from an index of that list, and it answers what member? answers: Ints and
# Floats that are ==, no NaN, lists by content, nothing in nil, and a value
# that is not a list refused only when a test reaches it.

row(
  "member_index.value.numbers_and_text",
  join_lines(
    [
      "def hits(xs, allowed)",
      "  filter((x) -> member?(x, allowed), xs)",
      "end",
      "",
      "hits([1, 2.0, 3, 4, \"a\", :b, nil, 0, 7, 8, 9, 10, 11, 12], [2, 3.0, \"a\", nil, -0.0, 12])"
    ]
  ),
  value("[2.0, 3, \"a\", nil, 0, 12]")
)

row(
  "member_index.value.nan_and_lists",
  join_lines(
    [
      "def kept(xs, allowed)",
      "  map((x) -> member?(x, allowed), xs)",
      "end",
      "",
      "z = 0.0",
      "kept([[1], [2], [1.0], 5, 5, 5, 5, 5, 5, 5, 5, 5], [[1], 6])"
    ]
  ),
  value("[true, false, true, false, false, false, false, false, false, false, false, false]")
)

row(
  "member_index.value.count_over_a_long_loop",
  join_lines(
    [
      "def hits(xs, allowed)",
      "  reduce((a, x) -> if member?(x, allowed)",
      "    a + 1",
      "  else",
      "    a",
      "  end, 0, xs)",
      "end",
      "",
      "hits(range(500), range(250, 750))"
    ]
  ),
  value("250")
)

row(
  "member_index.nil.holds_nothing",
  join_lines(
    [
      "def hits(xs, allowed)",
      "  filter((x) -> member?(x, allowed), xs)",
      "end",
      "",
      "hits(range(20), nil)"
    ]
  ),
  value("[]")
)

row(
  "member_index.error.a_loop_that_never_tests_never_raises",
  join_lines(
    [
      "def hits(xs, allowed)",
      "  filter((x) -> member?(x, allowed), xs)",
      "end",
      "",
      "def go(n)",
      "  hits([], n)",
      "end",
      "",
      "go(json_parse(\"5\"))"
    ]
  ),
  value("[]")
)

row(
  "member_index.error.not_a_list_raises_at_the_test",
  join_lines(
    [
      "def hits(xs, allowed)",
      "  filter((x) -> member?(x, allowed), xs)",
      "end",
      "",
      "def go(n)",
      "  hits([1], n)",
      "end",
      "",
      "go(json_parse(\"5\"))"
    ]
  ),
  fails(:eval, "expected list")
)
