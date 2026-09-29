# Control flow: if/elsif/else, unless, case/when, the boolean operators, while,
# begin and when. Only false and nil are falsy.

row(
  "control.if",
  "if 1 < 2\n  :yes\nelse\n  :no\nend",
  value(":yes"),
  covers("keyword:if", "keyword:else", "keyword:end")
)

row("control.if.no_else_is_nil", "if false\n  1\nend", value("nil"))

row(
  "control.elsif",
  "x = 5\nif x < 3\n  :small\nelsif x < 10\n  :medium\nelse\n  :large\nend",
  value(":medium"),
  covers("keyword:elsif")
)

row(
  "control.unless",
  "unless false\n  :ran\nend",
  value(":ran"),
  covers("keyword:unless")
)

row(
  "control.truthiness",
  "[if 0\n  :t\nend, if \"\"\n  :t\nend, if []\n  :t\nend, if nil\n  :t\nelse\n  :f\nend]",
  value("[:t, :t, :t, :f]"),
  covers("keyword:if")
)

row(
  "control.true_false",
  "[true, false]",
  value("[true, false]"),
  covers("keyword:true", "keyword:false")
)

row(
  "control.case",
  "case 2\nwhen 1\n  :one\nwhen 2\n  :two\nelse\n  :other\nend",
  value(":two"),
  covers("keyword:case")
)

row(
  "control.case.else",
  "case 9\nwhen 1\n  :one\nelse\n  :other\nend",
  value(":other")
)

row(
  "control.case.uses_eq",
  "case 2.0\nwhen 2\n  :matched\nelse\n  :no\nend",
  value(":matched")
)

row(
  "control.case.destructure",
  "case [1, 2]\nwhen [a, b]\n  a + b\nend",
  value("3"),
  pending("G13")
)

row(
  "control.and",
  "[true && 2, false && 1, nil && 1]",
  value("[2, false, nil]"),
  covers("op:&&")
)

row("control.and.short_circuit", "x = false && 1 / 0\nx", value("false"))
row("control.or", "[nil || 3, 1 || 1 / 0]", value("[3, 1]"), covers("op:||"))
row("control.and.builtin", "and(1, 2, 3)", value("3"), covers("builtin:and"))
row("control.or.builtin", "or(false, nil, 4)", value("4"), covers("builtin:or"))

row(
  "control.not",
  "[!nil, !0, not(false)]",
  value("[true, false, true]"),
  covers("form:!x"),
  covers("builtin:not")
)

row(
  "control.when",
  "[when(true, 1), when(false, 1)]",
  value("[1, nil]"),
  covers("builtin:when")
)

row("control.begin", "begin(1, 2, 3)", value("3"), covers("builtin:begin"))

row(
  "control.while",
  "i = 0\nwhile(i < 3, set!(i, i + 1))\ni",
  value("3"),
  covers("builtin:while", "builtin:set!")
)

row(
  "control.comment",
  "comment(anything, at, all)",
  value("nil"),
  covers("builtin:comment")
)

row(
  "control.cond",
  "cond([1 > 2, :a], [true, :b])",
  value(":b"),
  pending("G1"),
  covers("builtin:cond")
)
