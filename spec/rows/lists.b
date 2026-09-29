# Lists: the literal, nil against [] (okite D0004), the empty list (D0011), and
# the list built-ins. Argument order is Lisp's: the list comes last.

row(
  "lists.literal",
  "[1, \"a\"]",
  value("[1, \"a\"]"),
  covers("form:[1, \"a\"]")
)

row("lists.empty", "[]", value("[]"))
row("lists.nested", "[[1], [2, [3]]]", value("[[1], [2, [3]]]"))
row("lists.equality", "[1, 2] == [1.0, 2.0]", value("true"))

row(
  "lists.nil_is_not_empty",
  "[nil == [], [] == [], nil == nil]",
  value("[false, true, true]"),
  covers("okite:D0004", "keyword:nil")
)

row(
  "lists.nil.list_p",
  "list?(nil)",
  value("false"),
  covers("okite:D0010"),
  covers("builtin:list?")
)

row("lists.nil.length_raises", "length(nil)", fails(:eval, "got nil"))
row("lists.no_indexing", "y = xs[0]", fails(:parse, "`nth(0, xs)`"))

row(
  "lists.append",
  "append([1, 2], [3])",
  value("[1, 2, 3]"),
  covers("builtin:append")
)

row("lists.append.none", "append()", value("[]"), covers("okite:D0011"))
row("lists.append.empty", "append([], [])", value("[]"))

row(
  "lists.butlast",
  "butlast([1, 2, 3])",
  value("[1, 2]"),
  covers("builtin:butlast")
)

row("lists.car", "car([1, 2])", value("1"), covers("builtin:car"))
row("lists.car.empty", "car([])", fails(:eval, "car of empty list"))
row("lists.cdr", "cdr([1])", value("[]"), covers("builtin:cdr"))
row("lists.cons", "cons(0, [1])", value("[0, 1]"), covers("builtin:cons"))
row("lists.count", "count([1, 2, 3])", value("3"), covers("builtin:count"))

row(
  "lists.distinct",
  "distinct([1, 1.0, 2, 1])",
  value("[1, 2]"),
  covers("builtin:distinct"),
  covers("okite:D0003")
)

row("lists.drop", "drop(1, [1, 2, 3])", value("[2, 3]"), covers("builtin:drop"))
row("lists.drop.all", "drop(1, [1])", value("[]"))
row("lists.first", "first([7, 8])", value("7"), covers("builtin:first"))
row("lists.first.empty", "first([])", fails(:eval, "car of empty list"))

row(
  "lists.flatten",
  "flatten([1, [2, [3]]])",
  value("[1, 2, 3]"),
  covers("builtin:flatten")
)

row(
  "lists.fourth",
  "fourth([1, 2, 3, 4])",
  value("4"),
  covers("builtin:fourth")
)

row(
  "lists.frequencies",
  "frequencies([\"a\", \"b\", \"a\"])",
  value("{\"a\" => 2, \"b\" => 1}"),
  covers("builtin:frequencies")
)

row(
  "lists.interleave",
  "interleave([1, 2], [:a, :b])",
  value("[1, :a, 2, :b]"),
  covers("builtin:interleave")
)

row(
  "lists.intersperse",
  "intersperse(0, [1, 2, 3])",
  value("[1, 0, 2, 0, 3]"),
  covers("builtin:intersperse")
)

row(
  "lists.iterate",
  "iterate(fn(x) x * 2 end, 1, 4)",
  value("[1, 2, 4, 8]"),
  covers("builtin:iterate")
)

row("lists.last", "last([1, 2, 3])", value("3"), covers("builtin:last"))
row("lists.length", "length([1, 2])", value("2"), covers("builtin:length"))
row("lists.list", "list(1, 2)", value("[1, 2]"), covers("builtin:list"))

row(
  "lists.member",
  "member?(1.0, [1, 2])",
  value("true"),
  covers("builtin:member?")
)

row("lists.next", "next([1])", value("[]"), covers("builtin:next"))
row("lists.nth", "nth(1, [:a, :b])", value(":b"), covers("builtin:nth"))
row("lists.nth.out_of_range", "nth(5, [1])", value("nil"))

row(
  "lists.partition",
  "partition(fn(x) x > 1 end, [1, 2, 3])",
  value("[[2, 3], [1]]"),
  covers("builtin:partition")
)

row(
  "lists.position",
  "position({a: 1}, [0, {a: 1}])",
  value("1"),
  covers("builtin:position")
)

row(
  "lists.range",
  "range(0, 4)",
  value("[0, 1, 2, 3]"),
  covers("builtin:range")
)

row("lists.range.step", "range(0, 10, 3)", value("[0, 3, 6, 9]"))
row("lists.range.empty", "range(0, 0)", value("[]"))

row(
  "lists.repeatedly",
  "repeatedly(fn() 1 end, 3)",
  value("[1, 1, 1]"),
  covers("builtin:repeatedly")
)

row("lists.rest", "rest([1])", value("[]"), covers("builtin:rest"))

row(
  "lists.reverse",
  "reverse([1, 2, 3])",
  value("[3, 2, 1]"),
  covers("builtin:reverse")
)

row("lists.second", "second([1, 2])", value("2"), covers("builtin:second"))

row(
  "lists.sort_keyed",
  "sort_keyed(fn(x) 0 - x end, [1, 3, 2])",
  value("[3, 2, 1]"),
  covers("builtin:sort_keyed")
)

row("lists.take", "take(2, [1, 2, 3])", value("[1, 2]"), covers("builtin:take"))
row("lists.take.zero", "take(0, [1])", value("[]"))
row("lists.third", "third([1, 2, 3])", value("3"), covers("builtin:third"))

row(
  "lists.zip",
  "zip([1, 2], [:a, :b])",
  value("[[1, :a], [2, :b]]"),
  covers("builtin:zip")
)

row(
  "lists.append.linear",
  "reduce(fn(acc, x) append(acc, [x]) end, [], range(0, 2000)) |> length()",
  value("2000")
)
