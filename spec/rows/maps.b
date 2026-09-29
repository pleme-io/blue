# Maps: the literal, value equality, exact keys (okite D0009), and the map
# built-ins. A map's keys cannot be listed from blue today (G1); those rows
# state the destination.

row(
  "maps.literal",
  "{a: 1, \"k\" => 2}",
  value("{\"k\" => 2, a: 1}"),
  covers("form:{a: 1, \"k\" => 2}")
)

row("maps.empty", "{}", value("{}"))

row(
  "maps.equality",
  "{a: 1, b: 2} == {b: 2, a: 1}",
  value("true"),
  covers("okite:D0001", "op:==")
)

row(
  "maps.inequality",
  "[{a: 1} != {a: 2}, {a: 1} != {b: 1}, {} == {}]",
  value("[true, true, true]")
)

row(
  "maps.exact_keys",
  "get(assoc({}, 1, :int), 1.0)",
  value("nil"),
  covers("okite:D0009")
)

row(
  "maps.assoc",
  "assoc({a: 1}, :b, 2)",
  value("{a: 1, b: 2}"),
  covers("builtin:assoc")
)

row("maps.assoc.replace", "assoc({a: 1}, :a, 9)", value("{a: 9}"))

row(
  "maps.dissoc",
  "dissoc({a: 1, b: 2}, :a)",
  value("{b: 2}"),
  covers("builtin:dissoc")
)

row("maps.get", "get({a: 1}, :a)", value("1"), covers("builtin:get"))
row("maps.get.absent", "get({a: 1}, :z)", value("nil"))

row(
  "maps.zipmap",
  "zipmap([:a, :b], [1, 2])",
  value("{a: 1, b: 2}"),
  covers("builtin:zipmap")
)

row(
  "maps.map_p",
  "[map?({}), map?([])]",
  value("[true, false]"),
  covers("builtin:map?")
)

row("maps.keys", "keys({a: 1, b: 2})", value("[:a, :b]"), pending("G1"))
row("maps.values", "values({a: 1, b: 2})", value("[1, 2]"), pending("G1"))

row(
  "maps.assoc.linear",
  "reduce(fn(m, i) assoc(m, i, i) end, {}, range(0, 2000)) |> get(1999)",
  value("1999")
)
