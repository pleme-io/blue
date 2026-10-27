# The one formatting: every alternative spelling has one canonical form, the
# canonical form formats to itself, and comments survive. Observed by
# `blue fmt` and in-process.

row(
  "fmt.canonical_is_fixed",
  unlines(["def f(x)", "  x + 1", "end"]),
  formats(unlines(["def f(x)", "  x + 1", "end"]))
)

row(
  "fmt.unless",
  join_lines(["unless x", "  1", "end"]),
  formats(unlines(["if not x", "  1", "end"]))
)

row("fmt.send_to_call", "x.f(y)", formats(unlines(["f(x, y)"])))

row(
  "fmt.else_if",
  join_lines(["if a", "  1", "else", "  if b", "    2", "  end", "end"]),
  formats(unlines(["if a", "  1", "elsif b", "  2", "end"]))
)

row("fmt.unary_minus", "0 - x", formats(unlines(["-x"])))
row("fmt.not", "not(x)", formats(unlines(["not x"])))
row("fmt.define", "define(x, 5)", formats(unlines(["x = 5"])))

row(
  "fmt.comments_survive",
  join_lines(["# a comment", "x = 1", "", "# another", "y = 2"]),
  formats(unlines(["# a comment", "x = 1", "", "# another", "y = 2"]))
)

row("fmt.spacing", "x=[1,2,  3]", formats(unlines(["x = [1, 2, 3]"])))

row(
  "fmt.map_keys",
  "{:a => 1, \"k\" => 2}",
  formats(unlines(["{a: 1, \"k\" => 2}"]))
)

row(
  "fmt.interpolation",
  join_lines(["n = 1", "\"n = #\u{7b}n}\""]),
  formats(unlines(["n = 1", "\"n = #\u{7b}n}\""]))
)

row("fmt.pipe", "xs |> f(a)", formats(unlines(["f(xs, a)"])))

row(
  "fmt.long_call_breaks",
  "f(aaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbb, cccccccccccccccccccccc, dddddddddddddddddd)",
  formats(
    unlines(
      [
        "f(",
        "  aaaaaaaaaaaaaaaaaaaa,",
        "  bbbbbbbbbbbbbbbbbbbbbbbbb,",
        "  cccccccccccccccccccccc,",
        "  dddddddddddddddddd",
        ")"
      ]
    )
  )
)

row(
  "fmt.fn",
  join_lines(["map(fn(x)", "  x * 2", "end, xs)"]),
  formats(unlines(["map((x) -> x * 2, xs)"]))
)

row(
  "fmt.fn_block",
  join_lines(["each(xs, fn(x) a(x)", "b(x) end)"]),
  formats(
    unlines(["each(", "  xs,", "  fn(x)", "    a(x)", "    b(x)", "  end", ")"])
  )
)

row(
  "fmt.qualified_name",
  join_lines(["use(\"sp_mod\")", "sp_mod::sp_twice(2)"]),
  formats(unlines(["use(\"sp_mod\")", "sp_mod::sp_twice(2)"]))
)
