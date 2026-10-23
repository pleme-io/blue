# Maps: the literal, value equality, exact keys (okite D0009), and the map
# built-ins. A map's keys cannot be listed from blue today (G1); those rows
# state the destination.

row(
  "maps.literal",
  "{a: 1, \"k\" => 2}",
  value("{\"k\" => 2, a: 1}"),
  covers("form:{a: 1, \"k\" => 2}")
)

row(
  "maps.pun",
  "a = 1\nb = 2\n{a:, b:}",
  value("{a: 1, b: 2}"),
  covers("form:{a:, b:}")
)

row(
  "maps.pun.mixed",
  "a = 1\n{a:, n: 3, \"k\" => a}",
  value("{\"k\" => 1, a: 1, n: 3}")
)

row(
  "maps.pun.multiline",
  "a = 1\nb = 2\n{\n  a:,\n  b:\n}",
  value("{a: 1, b: 2}")
)

row("maps.pun.predicate", "ok? = true\n{ok?:}", value("{ok?: true}"))

row("maps.pun.unbound", "{missing:}", fails(:check, "B0001"))

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

row(
  "maps.map_entries",
  "map_entries({b: 2, a: 1})",
  value("[[:a, 1], [:b, 2]]"),
  covers("builtin:map_entries")
)

row(
  "maps.dig",
  "m = {a: {b: [10, 20, {c: 3}]}}\n[dig(m, :a, :b, 2, :c), dig(m, :a, :b, -1, :c), dig(m)]",
  value("[3, 3, {a: {b: [10, 20, {c: 3}]}}]"),
  covers("builtin:dig")
)

row(
  "maps.dig.total",
  "m = {a: {b: [10]}}\n[dig(m, :a, :q, :c), dig(m, :a, :b, 9), dig(m, :a, :b, 0, :x), dig(nil, :a), dig(5, :a)]",
  value("[nil, nil, nil, nil, nil]")
)

row(
  "maps.dig.keys_are_data",
  "m = {\"app.kubernetes.io/name\" => {1 => :one}}\n[dig(m, \"app.kubernetes.io/name\", 1), dig(m, :app)]",
  value("[:one, nil]")
)

row(
  "maps.dig.splatted",
  "path = [:a, :b]\ndig(*cons({a: {b: 1}}, path))",
  value("1")
)

row(
  "maps.bury",
  "bury({}, :a, :b, :c, 1)",
  value("{a: {b: {c: 1}}}"),
  covers("builtin:bury")
)

row(
  "maps.bury.returns_a_new_tree",
  "m = {a: {b: 1}}\nn = bury(m, :a, :c, 2)\n[m, n]",
  value("[{a: {b: 1}}, {a: {b: 1, c: 2}}]")
)

row(
  "maps.bury.lists",
  "m = {a: [1, 2]}\n[bury(m, :a, 0, 9), bury(m, :a, 2, 3), bury(m, :a, -1, 7)]",
  value("[{a: [9, 2]}, {a: [1, 2, 3]}, {a: [1, 7]}]")
)

row(
  "maps.bury.refuses_a_leaf",
  "bury({a: 1}, :a, :b, 2)",
  fails(:eval, "bad_path: the value at step 1 is int")
)

row(
  "maps.bury.refuses_an_index_past_the_end",
  "bury({a: [1]}, :a, 5, 2)",
  fails(:eval, "5 is not an index of a list of 1 elements")
)

row(
  "maps.bury.replaces_a_leaf_at_the_end",
  "bury({a: 1}, :a, 2)",
  value("{a: 2}")
)

row(
  "maps.dig_bury_round_trip",
  "facts = [[[:a, :b], 1], [[:a, :c], 2], [[:d], 3]]\nt = reduce((acc, f) -> bury(*append([acc], first(f), [last(f)])), {}, facts)\n[t, map((f) -> dig(*cons(t, first(f))) == last(f), facts)]",
  value("[{a: {b: 1, c: 2}, d: 3}, [true, true, true]]")
)
