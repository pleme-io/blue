# Control flow: if/elsif/else, unless, case/when, the boolean operators, while,
# begin and when. Only false and nil are falsy.

row(
  "control.if",
  join_lines(["if 1 < 2", "  :yes", "else", "  :no", "end"]),
  value(":yes"),
  covers("keyword:if", "keyword:else", "keyword:end")
)

row(
  "control.if.no_else_is_nil",
  join_lines(["if false", "  1", "end"]),
  value("nil")
)

row(
  "control.elsif",
  join_lines(
    [
      "x = 5",
      "if x < 3",
      "  :small",
      "elsif x < 10",
      "  :medium",
      "else",
      "  :large",
      "end"
    ]
  ),
  value(":medium"),
  covers("keyword:elsif")
)

row(
  "control.unless",
  join_lines(["unless false", "  :ran", "end"]),
  value(":ran"),
  covers("keyword:unless")
)

row(
  "control.truthiness",
  join_lines(
    [
      "[if 0",
      "  :t",
      "end, if \"\"",
      "  :t",
      "end, if []",
      "  :t",
      "end, if nil",
      "  :t",
      "else",
      "  :f",
      "end]"
    ]
  ),
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
  join_lines(
    [
      "case 2",
      "when 1",
      "  :one",
      "when 2",
      "  :two",
      "else",
      "  :other",
      "end"
    ]
  ),
  value(":two"),
  covers("keyword:case")
)

row(
  "control.case.else",
  join_lines(["case 9", "when 1", "  :one", "else", "  :other", "end"]),
  value(":other")
)

row(
  "control.case.uses_eq",
  join_lines(["case 2.0", "when 2", "  :matched", "else", "  :no", "end"]),
  value(":matched")
)

row(
  "control.case.destructure",
  join_lines(["case [1, 2]", "when [a, b]", "  a + b", "end"]),
  value("3"),
  pending("G13")
)

row(
  "control.and",
  "[true and 2, false and 1, nil and 1]",
  value("[2, false, nil]"),
  covers("op:and")
)

row(
  "control.and.short_circuit",
  join_lines(["x = false && 1 / 0", "x"]),
  value("false")
)

row("control.or", "[nil or 3, 1 or 1 / 0]", value("[3, 1]"), covers("op:or"))
row("control.and.symbol", "[true && 2, nil || 3]", value("[2, 3]"))
row("control.and.builtin", "and(1, 2, 3)", value("3"))
row("control.or.builtin", "or(false, nil, 4)", value("4"))

row(
  "control.not",
  "[!nil, !0, not(false)]",
  value("[true, false, true]"),
  covers("form:not x")
)

row(
  "control.when",
  "[when(true, 1), when(false, 1)]",
  value("[1, nil]"),
  covers("builtin:when")
)

row("control.begin", "begin(1, 2, 3)", value("3"), covers("keyword:begin"))

row(
  "control.while",
  join_lines(["i = 0", "while(i < 3, set!(i, i + 1))", "i"]),
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
