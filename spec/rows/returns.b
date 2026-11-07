# Guard-clause return: a `return` that ends a branch of an `if` or `case` in
# a def body is rewritten into if/else before anything runs; anywhere else it
# is refused (B0080). docs/GUARD-RETURN.md.

row(
  "returns.guard",
  join_lines(
    [
      "def grade(n)",
      "  if n < 50",
      "    return :low",
      "  end",
      "  :high",
      "end",
      "[grade(10), grade(90)]"
    ]
  ),
  value("[:low, :high]"),
  covers("keyword:return")
)

row(
  "returns.bare_is_nil",
  join_lines(
    ["def f(n)", "  if n < 0", "    return", "  end", "  n", "end", "f(-1)"]
  ),
  value("nil")
)

row(
  "returns.case_arm",
  join_lines(
    [
      "def size(x)",
      "  case x",
      "  when 0",
      "    return :none",
      "  end",
      "  :some",
      "end",
      "[size(0), size(5)]"
    ]
  ),
  value("[:none, :some]")
)

row(
  "check.B0080",
  join_lines(["def f(xs)", "  map((x) -> return x, xs)", "end"]),
  diagnoses(["B0080"]),
  covers("rule:B0080")
)

row("check.B0080.stops_the_run", "return 1", fails(:check, "B0080"))

row(
  "returns.code_after_return",
  join_lines(["def f()", "  return 1", "  2", "end"]),
  fails(:parse, "never runs")
)
