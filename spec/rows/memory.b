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
# Memory rows (docs/PURE-BLUE.md C2, invariant I3): a run leaves nothing live.
# leaks(N) runs the program once to warm the evaluator, then three more times,
# and reads the counting allocator's bytes retained per run.

row(
  "memory.a_built_list_is_freed",
  join_lines(["xs = map((i) -> [i, i * 2], range(0, 200))", "length(xs)"]),
  leaks(0)
)

row(
  "memory.a_closure_and_its_captures_are_freed",
  join_lines(["k = 3", "add = (x) -> x + k", "length(map(add, range(0, 50)))"]),
  leaks(0)
)

row(
  "memory.a_cell_is_freed",
  join_lines(["c = cell([1, 2, 3])", "cell_put(c, [4])", "length(cell_get(c))"]),
  leaks(0)
)
