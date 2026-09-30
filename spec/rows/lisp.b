# tatara-lisp forms bound in every blue interpreter. Several take a binding
# list that has no blue spelling; their rows state what blue does with the name.

row(
  "lisp.letrec",
  "letrec([[f, fn(n) n end]], f(1))",
  fails(:check, "B0001"),
  covers("builtin:letrec")
)

row("lisp.match", "match(1, [1, :one])", value(":one"), covers("builtin:match"))

row(
  "lisp.dolist",
  "dolist([x, [1, 2]], x)",
  fails(:eval, "unbound symbol `x`"),
  covers("builtin:dolist"),
  pending("G19", "vm")
)

row(
  "lisp.doseq",
  "doseq([x, [1, 2]], x)",
  fails(:eval, "unbound symbol `x`"),
  covers("builtin:doseq"),
  pending("G19", "vm")
)

row(
  "lisp.dotimes",
  "dotimes([i, 3], i)",
  fails(:eval, "unbound symbol `i`"),
  covers("builtin:dotimes"),
  pending("G19", "vm")
)

row(
  "lisp.provide",
  "provide(x)",
  fails(:eval, "only valid at module top level"),
  covers("builtin:provide"),
  pending("G19", "vm")
)

row(
  "lisp.require",
  "require(x)",
  fails(:eval, "first arg must be a string path"),
  covers("builtin:require"),
  pending("G19", "vm")
)

row(
  "lisp.defactor",
  "defactor(counter, 0, fn(s, m) s + m end)",
  value("nil"),
  covers("builtin:defactor")
)

row(
  "lisp.defcommand",
  "defcommand(bus, cmd, [x], x)",
  fails(:eval, "unbound symbol `bus`"),
  covers("builtin:defcommand"),
  pending("G19", "vm")
)

row(
  "lisp.defquery",
  "defquery(bus, qry, [x], x)",
  fails(:eval, "unbound symbol `bus`"),
  covers("builtin:defquery"),
  pending("G19", "vm")
)

row(
  "lisp.defflow",
  "defflow(flow, fn(x) x + 1 end, fn(x) x * 2 end)\nflow(3)",
  value("8"),
  covers("builtin:defflow")
)

row(
  "lisp.defsm",
  "defsm(m, :initial, :a, :transitions, [[:a, :go, :b]])",
  value("nil"),
  covers("builtin:defsm")
)

row(
  "lisp.defstrategy",
  "defstrategy(st, :x, fn() 1 end, :default, fn() 2 end)",
  value("nil"),
  covers("builtin:defstrategy")
)

row(
  "lisp.defvisitor",
  "defvisitor(vis, :x, fn(n) n end, :default, fn(n) 0 end)",
  value("nil"),
  covers("builtin:defvisitor")
)

row(
  "lisp.builtin_names",
  "[member?(\"length\", builtin_names()), member?(\"no_such_name\", builtin_names())]",
  value("[true, false]"),
  covers("builtin:builtin_names")
)
