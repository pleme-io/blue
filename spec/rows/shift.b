# The blueshift (theory/BLUE.md V.20): the rung a program sits at, what holds
# it back, and behaviour that legitimately differs by rung. A `shifts` row is
# observed by `blue shift` and in-process; `position` states the rung a row's
# behaviour applies at, and the runner checks the program measures there.

row(
  "shift.spec_file",
  join_lines(
    [
      "def shifted(n: Int) -> Int",
      "  n * 2",
      "end",
      "",
      "def loose(n)",
      "  n * 3",
      "end"
    ]
  ),
  shifts("annotated", ["loose"]),
  position("annotated")
)

row(
  "shift.spec_file.same_answer",
  join_lines(
    [
      "def shifted(n: Int) -> Int",
      "  n * 2",
      "end",
      "",
      "def loose(n)",
      "  n * 3",
      "end",
      "",
      "[shifted(2), loose(2), shifted(5) == loose(5) - 5]"
    ]
  ),
  value("[4, 6, true]"),
  position("annotated")
)

row(
  "shift.dynamic",
  join_lines(["def add(a, b)", "  a + b", "end"]),
  shifts("dynamic", ["add"]),
  position("dynamic")
)

row(
  "shift.checked",
  join_lines(["def add(a: Int, b: Int) -> Int", "  a + b", "end"]),
  shifts("checked", []),
  position("checked")
)

row(
  "shift.restricted",
  join_lines(
    [
      "definput(\"schema\", \"b3:abc\")",
      "",
      "def add(a: Int, b: Int) -> Int",
      "  a + b",
      "end"
    ]
  ),
  shifts("restricted", []),
  position("restricted")
)

row(
  "shift.capability_does_not_rescue",
  join_lines(
    ["definput(\"schema\", \"b3:abc\")", "", "def add(a, b)", "  a + b", "end"]
  ),
  shifts("dynamic", ["add"]),
  position("dynamic")
)

row(
  "shift.lowest_wins",
  join_lines(
    [
      "def a(n: Int) -> Int",
      "  n",
      "end",
      "",
      "def b(n)",
      "  n",
      "end",
      "",
      "def c(n)",
      "  n",
      "end"
    ]
  ),
  shifts("annotated", %w[b c]),
  position("annotated")
)

row("shift.no_declarations", "1 + 1", shifts("none", []))
row("shift.unparseable", unlines(["def f("]), shifts("none", []))

row(
  "shift.wrong_arg.dynamic",
  join_lines(["def f(n)", "  n + 1", "end", "", "f(\"a\")"]),
  fails(:eval, "expected number"),
  position("dynamic")
)

row(
  "shift.wrong_arg.annotated",
  join_lines(
    [
      "def f(n: Int) -> Int",
      "  n + 1",
      "end",
      "",
      "def g(x)",
      "  f(x)",
      "end",
      "",
      "g(\"a\")"
    ]
  ),
  fails(:eval, "argument 1 expects Int"),
  position("annotated"),
  pending("G8")
)

row(
  "shift.wrong_arg.checked",
  join_lines(
    [
      "def f(n: Int) -> Int",
      "  n + 1",
      "end",
      "",
      "def g() -> Int",
      "  f(\"a\")",
      "end",
      "",
      "g"
    ]
  ),
  fails(:check, "B0005"),
  position("checked")
)

row(
  "shift.runs.dynamic",
  join_lines(["def f(n)", "  n * 2", "end", "", "f(21)"]),
  value("42"),
  position("dynamic")
)

row(
  "shift.runs.checked",
  join_lines(["def f(n: Int) -> Int", "  n * 2", "end", "", "f(21)"]),
  value("42"),
  position("checked")
)

row(
  "shift.runs.restricted",
  join_lines(
    [
      "definput(\"schema\", \"b3:abc\")",
      "",
      "def f(n: Int) -> Int",
      "  n * 2",
      "end",
      "",
      "f(21)"
    ]
  ),
  value("42"),
  position("restricted")
)
