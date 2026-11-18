# A string built by appends in a loop is built once (R13), and it is the
# string the loop builds: the start converted as the first step converts it,
# each step's parts in order, the start untouched for an empty list or nil,
# and a refusal where the loop would raise.

row(
  "builder.value.parts_in_order",
  join_lines(
    [
      "def build(n)",
      "  reduce((s, i) -> \"#\u{7b}s}<#\u{7b}i}>\", \"\", range(n))",
      "end",
      "",
      "build(4)"
    ]
  ),
  value("\"<0><1><2><3>\"")
)

row(
  "builder.value.a_start_that_is_no_string",
  join_lines(
    [
      "def build(xs)",
      "  reduce((s, x) -> \"#\u{7b}s}#\u{7b}x},\", 5, xs)",
      "end",
      "",
      "[build([1, 2.5, nil]), build([]), build(nil)]"
    ]
  ),
  value("[\"51,2.5,,\", 5, 5]")
)

row(
  "builder.fails.a_part_that_raises",
  join_lines(
    [
      "def build(xs)",
      "  reduce((s, x) -> \"#\u{7b}s}#\u{7b}10 / x}\", \"\", xs)",
      "end",
      "",
      "build([1, 0])"
    ]
  ),
  fails(:eval, "division by zero")
)
