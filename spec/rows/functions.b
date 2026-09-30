# Bindings, functions and closures: def, fn, recursion, higher-order built-ins
# (Lisp argument order: the function first), arity, and deep recursion (G6).

row(
  "bind.statement",
  "x = 5\nx + 1",
  value("6"),
  covers("form:x = 5"),
  covers("builtin:define")
)

row("bind.rebind", "x = 1\nx = 2\nx", value("2"))
row("bind.define", "define(y, 3)\ny", value("3"))
row("bind.set", "x = 1\nset!(x, 5)\nx", value("5"))

row(
  "bind.no_let",
  "x = let([[y, 1]], y)",
  fails(:check, "B0001"),
  covers("builtin:let")
)

row(
  "fn.def",
  "def double(n)\n  n * 2\nend\n\ndouble(21)",
  value("42"),
  covers("keyword:def", "form:f(x, y)")
)

row("fn.def.last_expression", "def f()\n  1\n  2\nend\n\nf()", value("2"))

row(
  "fn.anonymous",
  "f = fn(x) x * 2 end\nf(4)",
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
  "def adder(n)\n  fn(x) x + n end\nend\n\nadd2 = adder(2)\nadd2(5)",
  value("7")
)

row(
  "fn.closure.captures_value",
  "n = 1\nf = fn() n end\nn = 2\nf()",
  value("2")
)

row(
  "fn.recursion",
  "def fact(n)\n  if n < 2\n    1\n  else\n    n * fact(n - 1)\n  end\nend\n\nfact(10)",
  value("3628800")
)

row(
  "fn.tail_calls",
  "def spin(n, acc)\n  if n == 0\n    acc\n  else\n    spin(n - 1, acc + 1)\n  end\nend\n\nspin(100000, 0)",
  value("100000")
)

row(
  "fn.deep_recursion",
  "def depth(n)\n  if n == 0\n    0\n  else\n    1 + depth(n - 1)\n  end\nend\n\ndepth(100000)",
  fails(:eval, "depth"),
  isolate()
)

row(
  "fn.deep_recursion.catchable",
  "def depth(n)\n  if n == 0\n    0\n  else\n    1 + depth(n - 1)\n  end\nend\n\ntry(depth(100000), catch(_e(), :caught))",
  value(":caught"),
  isolate()
)

# Under a declared step budget: blue's default is unbounded (long runs are
# behaviour), and the suite runs every column under `ROW_STEPS` (the VM's 50M).
row(
  "fn.runaway_is_bounded",
  "def spin(n)\n  spin(n + 1)\nend\n\nspin(0)",
  fails(:eval, "budget"),
  isolate()
)

row(
  "fn.arity",
  "def f(a, b)\n  a\nend\n\nf(1)",
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
  fails(:eval, "expected list, got closure"),
  pending("G18", "vm")
)

row("fn.no_blocks", "xs.map { |x| x }", fails(:parse, "fn(x)"))

row(
  "fn.no_do",
  "each(xs) do |x|\n  x\nend",
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
  "comp(fn(x) x + 1 end, fn(x) x * 2 end)(5)",
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
  "find(fn(x) x > 1 end, [1, 2, 3])",
  value("2"),
  covers("builtin:find")
)

row(
  "fn.flip",
  "flip(fn(a, b) a - b end)(1, 10)",
  value("9"),
  covers("builtin:flip")
)

row(
  "fn.foldl",
  "foldl(fn(acc, x) acc - x end, 10, [1, 2])",
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
  "f = memoize(fn(x) x * x end)\n[f(3), f(3)]",
  value("[9, 9]"),
  covers("builtin:memoize")
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

row("fn.eval", "eval(quote\n  1 + 2\nend)", value("3"), covers("builtin:eval"))

row(
  "fn.gensym",
  "symbol?(gensym(\"g\"))",
  value("true"),
  covers("builtin:gensym")
)

row(
  "fn.rest_params",
  "def f(a, *rest)\n  rest\nend\n\nf(1, 2, 3)",
  value("[2, 3]"),
  pending("G13")
)
