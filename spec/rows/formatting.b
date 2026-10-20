# The one formatting: every alternative spelling has one canonical form, the
# canonical form formats to itself, and comments survive. Observed by
# `blue fmt` and in-process.

row(
  "fmt.canonical_is_fixed",
  "def f(x)\n  x + 1\nend\n",
  formats("def f(x)\n  x + 1\nend\n")
)

row("fmt.unless", "unless x\n  1\nend", formats("if not x\n  1\nend\n"))
row("fmt.send_to_call", "x.f(y)", formats("f(x, y)\n"))

row(
  "fmt.else_if",
  "if a\n  1\nelse\n  if b\n    2\n  end\nend",
  formats("if a\n  1\nelsif b\n  2\nend\n")
)

row("fmt.unary_minus", "0 - x", formats("-x\n"))
row("fmt.not", "not(x)", formats("not x\n"))
row("fmt.define", "define(x, 5)", formats("x = 5\n"))

row(
  "fmt.comments_survive",
  "# a comment\nx = 1\n\n# another\ny = 2",
  formats("# a comment\nx = 1\n\n# another\ny = 2\n")
)

row("fmt.spacing", "x=[1,2,  3]", formats("x = [1, 2, 3]\n"))
row("fmt.map_keys", "{:a => 1, \"k\" => 2}", formats("{a: 1, \"k\" => 2}\n"))

row(
  "fmt.interpolation",
  "n = 1\n\"n = #\u{7b}n}\"",
  formats("n = 1\n\"n = #\u{7b}n}\"\n")
)

row("fmt.pipe", "xs |> f(a)", formats("f(xs, a)\n"))

row(
  "fmt.long_call_breaks",
  "f(aaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbb, cccccccccccccccccccccc, dddddddddddddddddd)",
  formats("f(\n  aaaaaaaaaaaaaaaaaaaa,\n  bbbbbbbbbbbbbbbbbbbbbbbbb,\n  cccccccccccccccccccccc,\n  dddddddddddddddddd\n)\n")
)

row(
  "fmt.fn",
  "map(fn(x)\n  x * 2\nend, xs)",
  formats("map((x) -> x * 2, xs)\n")
)

row(
  "fmt.fn_block",
  "each(xs, fn(x) a(x)\nb(x) end)",
  formats("each(\n  xs,\n  fn(x)\n    a(x)\n    b(x)\n  end\n)\n")
)

row(
  "fmt.qualified_name",
  "use(\"sp_mod\")\nsp_mod::sp_twice(2)",
  formats("use(\"sp_mod\")\nsp_mod::sp_twice(2)\n")
)
