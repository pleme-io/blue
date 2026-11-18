row(
  "memory.last_use.straight_line",
  join_lines(["def f(x)", "  y = x + 1", "  y * x", "end"]),
  facts(["f: last_use y (* y x)", "f: last_use x (* y x)"])
)

row(
  "memory.last_use.read_twice_in_one_call",
  join_lines(["def sq(x)", "  x * x", "end"]),
  facts(["sq: last_use x (* x x)"])
)

row(
  "memory.last_use.per_branch",
  join_lines(
    ["def g(c, s)", "  if c", "    size(s)", "  else", "    0", "  end", "end"]
  ),
  facts(["g: last_use c (if c (size s) 0)", "g: last_use s (size s)"])
)

row(
  "memory.last_use.never_read",
  join_lines(["def k(x)", "  1", "end"]),
  facts([])
)
