# The blueshift (theory/BLUE.md V.20): the rung a program sits at, what holds
# it back, and behaviour that legitimately differs by rung. A `shifts` row is
# observed by `blue shift` and in-process; `position` states the rung a row's
# behaviour applies at, and the runner checks the program measures there.

row(
  "shift.spec_file",
  "def shifted(n: Int) -> Int\n  n * 2\nend\n\ndef loose(n)\n  n * 3\nend",
  shifts("annotated", ["loose"]),
  position("annotated")
)

row(
  "shift.spec_file.same_answer",
  "def shifted(n: Int) -> Int\n  n * 2\nend\n\ndef loose(n)\n  n * 3\nend\n\n[shifted(2), loose(2), shifted(5) == loose(5) - 5]",
  value("[4, 6, true]"),
  position("annotated")
)

row(
  "shift.dynamic",
  "def add(a, b)\n  a + b\nend",
  shifts("dynamic", ["add"]),
  position("dynamic")
)

row(
  "shift.checked",
  "def add(a: Int, b: Int) -> Int\n  a + b\nend",
  shifts("checked", []),
  position("checked")
)

row(
  "shift.restricted",
  "definput(\"schema\", \"b3:abc\")\n\ndef add(a: Int, b: Int) -> Int\n  a + b\nend",
  shifts("restricted", []),
  position("restricted")
)

row(
  "shift.capability_does_not_rescue",
  "definput(\"schema\", \"b3:abc\")\n\ndef add(a, b)\n  a + b\nend",
  shifts("dynamic", ["add"]),
  position("dynamic")
)

row(
  "shift.lowest_wins",
  "def a(n: Int) -> Int\n  n\nend\n\ndef b(n)\n  n\nend\n\ndef c(n)\n  n\nend",
  shifts("annotated", ["b", "c"]),
  position("annotated")
)

row("shift.no_declarations", "1 + 1", shifts("none", []))
row("shift.unparseable", "def f(\n", shifts("none", []))

row(
  "shift.wrong_arg.dynamic",
  "def f(n)\n  n + 1\nend\n\nf(\"a\")",
  fails(:eval, "expected number"),
  position("dynamic")
)

row(
  "shift.wrong_arg.annotated",
  "def f(n: Int) -> Int\n  n + 1\nend\n\ndef g(x)\n  f(x)\nend\n\ng(\"a\")",
  fails(:eval, "argument 1 expects Int"),
  position("annotated"),
  pending("G8")
)

row(
  "shift.wrong_arg.checked",
  "def f(n: Int) -> Int\n  n + 1\nend\n\ndef g() -> Int\n  f(\"a\")\nend\n\ng()",
  fails(:check, "B0005"),
  position("checked")
)

row(
  "shift.runs.dynamic",
  "def f(n)\n  n * 2\nend\n\nf(21)",
  value("42"),
  position("dynamic")
)

row(
  "shift.runs.checked",
  "def f(n: Int) -> Int\n  n * 2\nend\n\nf(21)",
  value("42"),
  position("checked")
)

row(
  "shift.runs.restricted",
  "definput(\"schema\", \"b3:abc\")\n\ndef f(n: Int) -> Int\n  n * 2\nend\n\nf(21)",
  value("42"),
  position("restricted")
)
