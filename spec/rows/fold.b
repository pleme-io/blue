# Folding: a call of a pure definition on literal arguments, where it can run
# more than once, is answered before the run, and nothing it observes changes:
# the same value of the same kind, the same error in the same place, and no
# error at all when the call never runs.

row(
  "fold.value.int",
  join_lines(
    [
      "def area(w, h)",
      "  w * h",
      "end",
      "",
      "def grow(xs)",
      "  map((x) -> x + area(3, 4), xs)",
      "end",
      "",
      "grow([1, 2])"
    ]
  ),
  value("[13, 14]")
)

row(
  "fold.kind.float_stays_float",
  join_lines(
    [
      "def scale(x)",
      "  x * 1.0",
      "end",
      "",
      "def half(x)",
      "  x / 2",
      "end",
      "",
      "def both(xs)",
      "  map((x) -> [scale(4), half(3), half(4)], xs)",
      "end",
      "",
      "both([0])"
    ]
  ),
  value("[[4.0, 1.5, 2]]")
)

row(
  "fold.kind.lists_nil_and_empty",
  join_lines(
    [
      "def pair(a)",
      "  [a, [a]]",
      "end",
      "",
      "def none(a)",
      "  []",
      "end",
      "",
      "def nothing(a)",
      "  nil",
      "end",
      "",
      "def all(xs)",
      "  map((x) -> [pair(\"s\"), none(1), nothing(1), none(1) == nil], xs)",
      "end",
      "",
      "all([0])"
    ]
  ),
  value("[[[\"s\", [\"s\"]], [], nil, false]]")
)

row(
  "fold.kind.keyword",
  join_lines(
    [
      "def level(n)",
      "  if n > 2",
      "    :high",
      "  else",
      "    :low",
      "  end",
      "end",
      "",
      "def levels(xs)",
      "  map((x) -> level(5), xs)",
      "end",
      "",
      "levels([0, 1])"
    ]
  ),
  value("[:high, :high]")
)

row(
  "fold.error.a_call_that_never_runs_never_raises",
  join_lines(
    [
      "def inv(x)",
      "  10 / x",
      "end",
      "",
      "def go(xs)",
      "  map((x) -> inv(0), xs)",
      "end",
      "",
      "go([])"
    ]
  ),
  value("[]")
)

row(
  "fold.error.raises_at_its_own_time",
  join_lines(
    [
      "def inv(x)",
      "  10 / x",
      "end",
      "",
      "def go(xs)",
      "  write_stdout(\"before\\n\")",
      "  map((x) -> inv(0), xs)",
      "end",
      "",
      "go([1])"
    ]
  ),
  fails(:eval, "division by zero")
)

row(
  "fold.budget.a_long_call_still_answers",
  join_lines(
    [
      "def spin(n)",
      "  reduce((a, x) -> a + x, 0, range(n))",
      "end",
      "",
      "def go(xs)",
      "  map((x) -> spin(300_000), xs)",
      "end",
      "",
      "go([0])"
    ]
  ),
  value("[44999850000]")
)
