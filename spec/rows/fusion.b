# Fusion: a chain of map, filter and reduce whose callbacks only compute runs as
# one pass, and nothing it observes changes: the same value, the same first
# error, the same output, on every evaluator, and an empty list stays empty.

row(
  "fusion.value.fold_filter_map",
  "reduce((a, x) -> a + x, 0, filter((x) -> x % 2 == 0, map((x) -> x * 3, range(10))))",
  value("60")
)

row(
  "fusion.value.map_map",
  "map((x) -> x + 1, map((x) -> x * 2, [1, 2, 3]))",
  value("[3, 5, 7]")
)

row(
  "fusion.value.filter_filter",
  "filter((x) -> x > 2, filter((x) -> x < 6, range(10)))",
  value("[3, 4, 5]")
)

row(
  "fusion.value.named_callbacks",
  join_lines(
    [
      "def sq(x)",
      "  x * x",
      "end",
      "",
      "def odd?(x)",
      "  x % 2 == 1",
      "end",
      "",
      "reduce((a, x) -> a + x, 0, filter(odd?, map(sq, [1, 2, 3])))"
    ]
  ),
  value("10")
)

row(
  "fusion.value.closure_over_a_local",
  join_lines(
    [
      "def scaled(xs, k)",
      "  reduce((a, x) -> a + x, 0, map((x) -> x * k, xs))",
      "end",
      "",
      "scaled([1, 2], 10)"
    ]
  ),
  value("30")
)

row(
  "fusion.empty.fold_returns_its_start",
  "reduce((a, x) -> a + x, 7, filter((x) -> x > 0, map((x) -> x * 2, [])))",
  value("7")
)

row(
  "fusion.empty.map_map",
  "map((x) -> x + 1, map((x) -> x * 2, []))",
  value("[]")
)

row(
  "fusion.error.the_inner_stage_raises_first",
  join_lines(
    [
      "def g(x)",
      "  if x == 3",
      "    length(nil)",
      "  else",
      "    x",
      "  end",
      "end",
      "",
      "def p(x)",
      "  10 / (x - 1) > 0",
      "end",
      "",
      "reduce((a, x) -> a + x, 0, filter(p, map(g, [0, 1, 2, 3])))"
    ]
  ),
  fails(:eval, "got nil")
)

row(
  "fusion.error.the_map_raises_before_the_fold_does",
  join_lines(
    [
      "def g(x)",
      "  if x == 2",
      "    length(nil)",
      "  else",
      "    x",
      "  end",
      "end",
      "",
      "reduce((a, x) -> a + 10 / (x - x), 0, map(g, [0, 1, 2]))"
    ]
  ),
  fails(:eval, "got nil")
)

row(
  "fusion.error.a_list_that_is_not_one",
  "reduce((a, x) -> a + x, 0, map((x) -> x * 2, json_parse(\"5\")))",
  fails(:eval, "expected list, got int")
)

row(
  "fusion.output.a_writing_callback_keeps_its_order",
  join_lines(
    [
      "def tg(x)",
      "  write_stdout(concat(\"g\", to_s(x), \" \"))",
      "  x",
      "end",
      "",
      "def tp(x)",
      "  write_stdout(concat(\"p\", to_s(x), \" \"))",
      "  true",
      "end",
      "",
      "write_stdout(to_s(reduce((a, x) -> a + x, 0, filter(tp, map(tg, [1, 2])))))"
    ]
  ),
  prints("g1 g2 p1 p2 3")
)
