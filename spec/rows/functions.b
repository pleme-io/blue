# Bindings, functions and closures: def, fn, recursion, higher-order built-ins
# (Lisp argument order: the function first), arity, and deep recursion (G6).

row(
  "bind.statement",
  join_lines(["x = 5", "x + 1"]),
  value("6"),
  covers("form:x = 5"),
  covers("builtin:define")
)

row("bind.rebind", join_lines(["x = 1", "x = 2", "x"]), value("2"))
row("bind.define", join_lines(["define(y, 3)", "y"]), value("3"))
row("bind.set", join_lines(["x = 1", "set!(x, 5)", "x"]), value("5"))

row(
  "bind.local.callee_keeps_its_own",
  join_lines(
    [
      "def inner()",
      "  k = 2",
      "  k",
      "end",
      "",
      "def outer()",
      "  k = 1",
      "  inner",
      "  k",
      "end",
      "",
      "outer"
    ]
  ),
  value("1")
)

row(
  "bind.local.recursion_keeps_each_frame",
  join_lines(
    [
      "def walk(n)",
      "  k = n",
      "  if n == 0",
      "    [k]",
      "  else",
      "    append(walk(n - 1), [k])",
      "  end",
      "end",
      "",
      "walk(3)"
    ]
  ),
  value("[0, 1, 2, 3]")
)

row(
  "bind.local.top_level_unchanged",
  join_lines(
    ["k = :top", "", "def f()", "  k = 1", "  k", "end", "", "[f, k]"]
  ),
  value("[1, :top]")
)

row(
  "bind.no_let",
  "x = let([[y, 1]], y)",
  fails(:check, "B0001"),
  covers("builtin:let")
)

row(
  "fn.def",
  join_lines(["def double(n)", "  n * 2", "end", "", "double(21)"]),
  value("42"),
  covers("keyword:def", "form:f(x, y)")
)

row(
  "fn.rest",
  join_lines(
    [
      "def pack(a, *rest)",
      "  [a, rest]",
      "end",
      "",
      "[pack(1), pack(1, 2, 3), pack(*[1, 2])]"
    ]
  ),
  value("[[1, []], [1, [2, 3]], [1, [2]]]"),
  covers("form:(a, *rest) -> rest")
)

row(
  "fn.rest.only",
  join_lines(["def all(*xs)", "  xs", "end", "", "[all(), all(1, 2)]"]),
  value("[[], [1, 2]]")
)

row(
  "fn.rest.lambda",
  join_lines(
    [
      "f = (h, *t) -> [h, t]",
      "g = fn(*xs)",
      "  xs",
      "end",
      "[f(1, 2, 3), g(4, 5)]"
    ]
  ),
  value("[[1, [2, 3]], [4, 5]]")
)

row(
  "fn.rest.typed",
  join_lines(
    ["def typed(a: Int, *rest) -> dyn", "  [a, rest]", "end", "", "typed(1, 2)"]
  ),
  value("[1, [2]]")
)

row(
  "fn.rest.too_few",
  join_lines(["def pack(a, b, *rest)", "  rest", "end", "", "pack(1)"]),
  fails(:eval, "expects at least 2 arguments, got 1"),
  pending("G19", "vm")
)

row(
  "fn.rest.not_last",
  join_lines(["def pack(*rest, a)", "  rest", "end"]),
  fails(:parse, "a rest parameter `*name` comes last")
)

row(
  "fmt.rest",
  join_lines(["def pack(a,*rest)", "  rest", "end"]),
  formats(unlines(["def pack(a, *rest)", "  rest", "end"]))
)

row(
  "fn.optional",
  join_lines(
    [
      "def pick(a, b?, c?)",
      "  [a, b, c]",
      "end",
      "",
      "[pick(1), pick(1, 2), pick(1, 2, 3)]"
    ]
  ),
  value("[[1, nil, nil], [1, 2, nil], [1, 2, 3]]"),
  covers("form:def f(a, b?) b end")
)

row(
  "fn.optional.typed",
  join_lines(
    [
      "def pick(a: Int, b?: Int) -> Int",
      "  a + (b or 10)",
      "end",
      "",
      "[pick(1), pick(1, 5)]"
    ]
  ),
  value("[11, 6]")
)

row(
  "fn.optional.too_many",
  join_lines(["def pick(a, b?)", "  [a, b]", "end", "", "pick(1, 2, 3)"]),
  fails(:eval, "takes 1 to 2 arguments, got 3")
)

row(
  "fn.optional.required_after",
  join_lines(["def pick(a?, b)", "  a", "end"]),
  fails(:parse, "cannot follow an optional one")
)

row(
  "fn.optional.rest_after",
  join_lines(["def pick(a, b?, *rest)", "  a", "end"]),
  fails(:parse, "a rest parameter cannot follow an optional one")
)

row(
  "fmt.optional",
  join_lines(["def pick(a,b?)", "  [a, b]", "end"]),
  formats(unlines(["def pick(a, b?)", "  [a, b]", "end"]))
)

row(
  "fn.def.bare_call",
  join_lines(["def f()", "  41", "end", "", "f + 1"]),
  value("42")
)

row(
  "fn.def.bare_call.condition",
  join_lines(
    ["def no()", "  false", "end", "", "if no", "  1", "else", "  2", "end"]
  ),
  value("2")
)

row(
  "fn.def.bare_call.local_is_its_value",
  join_lines(
    ["def f()", "  1", "end", "", "def g(f)", "  f + 10", "end", "", "g(5)"]
  ),
  value("15")
)

row(
  "fn.def.bare_call.value_form",
  join_lines(["def f()", "  2", "end", "", "apply(fn() f end, [])"]),
  value("2")
)

row(
  "fn.def.bare_call.arguments_stay_values",
  join_lines(["def inc(x)", "  x + 1", "end", "", "map(inc, [1, 2])"]),
  value("[2, 3]")
)

row(
  "fn.def.last_expression",
  join_lines(["def f()", "  1", "  2", "end", "", "f"]),
  value("2")
)

row(
  "fn.anonymous",
  join_lines(["f = fn(x) x * 2 end", "f(4)"]),
  value("8"),
  covers("keyword:fn"),
  covers("builtin:lambda")
)

row(
  "fn.value",
  "map(fn(x) x + 1 end, [1, 2])",
  value("[2, 3]"),
  covers("builtin:map")
)

row(
  "fn.closure",
  join_lines(
    [
      "def adder(n)",
      "  fn(x) x + n end",
      "end",
      "",
      "add2 = adder(2)",
      "add2(5)"
    ]
  ),
  value("7")
)

row(
  "fn.closure.captures_value",
  join_lines(["n = 1", "f = fn() n end", "n = 2", "f()"]),
  value("2")
)

row(
  "fn.recursion",
  join_lines(
    [
      "def fact(n)",
      "  if n < 2",
      "    1",
      "  else",
      "    n * fact(n - 1)",
      "  end",
      "end",
      "",
      "fact(10)"
    ]
  ),
  value("3628800")
)

row(
  "fn.tail_calls",
  join_lines(
    [
      "def spin(n, acc)",
      "  if n == 0",
      "    acc",
      "  else",
      "    spin(n - 1, acc + 1)",
      "  end",
      "end",
      "",
      "spin(100000, 0)"
    ]
  ),
  value("100000")
)

row(
  "fn.deep_recursion",
  join_lines(
    [
      "def depth(n)",
      "  if n == 0",
      "    0",
      "  else",
      "    1 + depth(n - 1)",
      "  end",
      "end",
      "",
      "depth(100000)"
    ]
  ),
  fails(:eval, "depth"),
  isolate()
)

row(
  "fn.deep_recursion.catchable",
  join_lines(
    [
      "def depth(n)",
      "  if n == 0",
      "    0",
      "  else",
      "    1 + depth(n - 1)",
      "  end",
      "end",
      "",
      "try(depth(100000), catch(_e(), :caught))"
    ]
  ),
  value(":caught"),
  isolate()
)

# Under a declared step budget: blue's default is unbounded (long runs are
# behaviour), and the suite runs every column under `ROW_STEPS` (the VM's 50M).
row(
  "fn.runaway_is_bounded",
  join_lines(["def spin(n)", "  spin(n + 1)", "end", "", "spin(0)"]),
  fails(:eval, "budget"),
  isolate()
)

row(
  "fn.arity",
  join_lines(["def f(a, b)", "  a", "end", "", "f(1)"]),
  fails(:eval, "f"),
  pending("G19", "vm")
)

row(
  "fn.method_call",
  "[1, 2].append([3])",
  value("[1, 2, 3]"),
  covers("form:x.f(y)")
)

row(
  "fn.pipe",
  "[3, 1] |> reverse()",
  value("[1, 3]"),
  covers("form:xs |> f(a)")
)

row(
  "fn.pipe.data_first_trap",
  "[1, 2] |> map(fn(x) x end)",
  fails(:check, "B0062")
)

row("fn.no_blocks", "xs.map { |x| x }", fails(:parse, "fn(x)"))

row(
  "fn.no_do",
  join_lines(["each(xs) do |x|", "  x", "end"]),
  fails(:parse, "`do`"),
  covers("keyword:do")
)

row(
  "fn.any",
  "any?(fn(x) x > 2 end, [1, 3])",
  value("true"),
  covers("builtin:any?")
)

row(
  "fn.apply",
  "apply(fn(a, b) a + b end, [1, 2])",
  value("3"),
  covers("builtin:apply")
)

row(
  "fn.comp",
  join_lines(
    [
      "# waive B0036: the row covers this name itself",
      "comp(fn(x) x + 1 end, fn(x) x * 2 end)(5)"
    ]
  ),
  value("11"),
  covers("builtin:comp")
)

row(
  "fn.compose",
  "compose(fn(x) x + 1 end, fn(x) x * 2 end)(5)",
  value("11"),
  covers("builtin:compose")
)

row("fn.const", "const(7)(1)", value("7"), covers("builtin:const"))

row(
  "fn.decorate",
  "decorate(fn(x) x end, :doc, \"id\")(3)",
  value("3"),
  covers("builtin:decorate")
)

row(
  "fn.every",
  "every?(fn(x) x > 0 end, [1, 2])",
  value("true"),
  covers("builtin:every?")
)

row(
  "fn.filter",
  "filter(fn(x) x % 2 == 0 end, [1, 2, 3, 4])",
  value("[2, 4]"),
  covers("builtin:filter")
)

row("fn.filter.empty", "filter(fn(_x) false end, [1])", value("[]"))

row(
  "fn.find",
  "find([1, 2, 3], fn(x) x > 1 end)",
  value("2"),
  covers("builtin:find")
)

row("fn.find.absent", "find([1, 2, 3], fn(x) x > 9 end)", value("nil"))

row("fn.find.empty", "find([], fn(_x) true end)", value("nil"))

row("fn.find.nil_is_empty", "find(nil, fn(_x) true end)", value("nil"))

row(
  "fn.find.function_first_is_bridged",
  join_lines(
    [
      "# waive B0062: the tatara-lisp callers pass the function first",
      "find(fn(x) x > 1 end, [1, 2, 3])"
    ]
  ),
  value("2")
)

row("fn.find.not_a_list", "find(5, fn(_x) true end)", fails(:check, "B0062"))

row(
  "fn.flat_map",
  "flat_map([1, 2, 3], fn(x) [x, x * 10] end)",
  value("[1, 10, 2, 20, 3, 30]"),
  covers("builtin:flat_map")
)

row(
  "fn.flat_map.nil_result_adds_nothing",
  join_lines(
    ["flat_map([1, 2], fn(x) if x == 1", "  nil", "else", "  [x]", "end end)"]
  ),
  value("[2]")
)

row("fn.flat_map.empty", "flat_map([], fn(x) [x] end)", value("[]"))

row(
  "fn.flat_map.function_first_is_refused",
  "flat_map(fn(x) [x] end, [1])",
  fails(:check, "B0062")
)

row(
  "fn.flat_map.result_not_a_list",
  "flat_map([1], fn(x) x end)",
  fails(:eval, "a list from f")
)

row(
  "fn.group_by",
  "group_by([1, 2, 3, 4, 5], fn(n) n % 2 end)",
  value("{0 => [2, 4], 1 => [1, 3, 5]}"),
  covers("builtin:group_by")
)

row("fn.group_by.empty", "group_by([], fn(x) x end)", value("{}"))

row(
  "fn.group_by.function_first_is_refused",
  "group_by(fn(x) x end, [1])",
  fails(:check, "B0062")
)

row(
  "fn.group_by.key_not_a_scalar",
  "group_by([1], fn(x) [x] end)",
  fails(:eval, "a group key must be a scalar")
)

row(
  "fn.flip",
  "flip(fn(a, b) a - b end)(1, 10)",
  value("9"),
  covers("builtin:flip")
)

row(
  "fn.foldl",
  join_lines(
    [
      "# waive B0036: the row covers this name itself",
      "foldl(fn(acc, x) acc - x end, 10, [1, 2])"
    ]
  ),
  value("7"),
  covers("builtin:foldl")
)

row(
  "fn.foldr",
  "foldr(fn(x, acc) cons(x, acc) end, [], [1, 2])",
  value("[1, 2]"),
  covers("builtin:foldr")
)

row("fn.identity", "identity(:x)", value(":x"), covers("builtin:identity"))

row(
  "fn.juxt",
  "juxt(fn(x) x + 1 end, fn(x) x * 2 end)(3)",
  value("[4, 6]"),
  covers("builtin:juxt")
)

row(
  "fn.map.many",
  "map(fn(a, b) a + b end, [1, 2], [10, 20])",
  value("[11, 22]")
)

row(
  "fn.memoize",
  join_lines(["f = memoize(fn(x) x * x end)", "[f(3), f(3)]"]),
  value("[9, 9]"),
  covers("builtin:memoize")
)

row(
  "fn.volatile",
  join_lines(["def f(x)", "  x * 2", "end", "volatile(f)", "[f(3), f(3)]"]),
  value("[6, 6]"),
  covers("builtin:volatile")
)

row(
  "fn.volatile.not_a_function",
  "volatile(3)",
  fails(:check, "B0062")
)

row(
  "fn.volatile.not_a_function_at_run_time",
  join_lines(["xs = [3]", "volatile(first(xs))"]),
  fails(:eval, "expected function")
)

row(
  "fn.partial",
  "partial(fn(a, b) a - b end, 10)(3)",
  value("7"),
  covers("builtin:partial")
)

row(
  "fn.pipe_fn",
  "pipe(fn(x) x + 1 end, fn(x) x * 2 end)(5)",
  value("12"),
  covers("builtin:pipe")
)

row(
  "fn.reduce",
  "reduce(fn(acc, x) acc + x end, 0, [1, 2, 3])",
  value("6"),
  covers("builtin:reduce")
)

row(
  "fn.reduce.no_init",
  "reduce(fn(acc, x) acc + x end, [1, 2, 3])",
  value("6")
)

row(
  "fn.remove",
  "remove(fn(x) x > 1 end, [1, 2, 3])",
  value("[1]"),
  covers("builtin:remove")
)

row(
  "fn.some",
  "some(fn(x) x > 1 end, [1, 2])",
  value("true"),
  covers("builtin:some")
)

row("fn.tap", "tap(fn(x) x + 100 end, 5)", value("5"), covers("builtin:tap"))

row(
  "fn.visit",
  "visit(fn(x) x end, [1, [2]])",
  value("[1, [2]]"),
  covers("builtin:visit")
)

row(
  "fn.eval",
  join_lines(["eval(quote", "  1 + 2", "end)"]),
  value("3"),
  covers("builtin:eval")
)

row(
  "fn.gensym",
  "symbol?(gensym(\"g\"))",
  value("true"),
  covers("builtin:gensym")
)

row(
  "fn.rest_params",
  join_lines(["def f(a, *rest)", "  rest", "end", "", "f(1, 2, 3)"]),
  value("[2, 3]")
)
