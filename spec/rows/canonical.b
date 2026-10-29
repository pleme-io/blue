# One way to write each thing (docs/CANONICAL-FORMS.md): each rule's canonical
# rewrite, and the forms and words it writes.

row("canon.B0024", "x   =   1", diagnoses(["B0024"]), covers("rule:B0024"))

row("canon.B0024.writes", "x   =   1", formats(unlines(["x = 1"])))

row(
  "canon.B0025",
  join_lines(["ready = true", "ready && ready"]),
  diagnoses(["B0025"]),
  covers("rule:B0025")
)

row(
  "canon.B0025.writes",
  "true && false || !true",
  formats(unlines(["true and false or not true"]))
)

row(
  "canon.B0025.negation_as_operand",
  "!a == b",
  formats(unlines(["(not a) == b"]))
)

row(
  "canon.B0026",
  join_lines(["unless false", "  1", "end"]),
  diagnoses(["B0026"]),
  covers("rule:B0026")
)

row(
  "canon.B0026.writes",
  join_lines(["unless false", "  1", "end"]),
  formats(unlines(["if not false", "  1", "end"]))
)

row(
  "canon.B0027",
  join_lines(
    [
      "a = 1",
      "if a == 1",
      "  1",
      "else",
      "  if a == 2",
      "    2",
      "  end",
      "end"
    ]
  ),
  diagnoses(["B0027"]),
  covers("rule:B0027")
)

row(
  "canon.B0027.writes",
  join_lines(
    [
      "a = 1",
      "if a == 1",
      "  1",
      "else",
      "  if a == 2",
      "    2",
      "  end",
      "end"
    ]
  ),
  formats(
    unlines(["a = 1", "", "if a == 1", "  1", "elsif a == 2", "  2", "end"])
  )
)

row(
  "canon.B0028",
  join_lines(["x = \"a\"", "x.concat(\"b\")"]),
  diagnoses(["B0028"]),
  covers("rule:B0028")
)

row(
  "canon.B0028.writes",
  join_lines(["x = \"a\"", "x.concat(\"b\")"]),
  formats(unlines(["x = \"a\"", "concat(x, \"b\")"]))
)

row(
  "canon.B0028.pipe",
  join_lines(["xs = [1]", "xs |> count"]),
  formats(unlines(["xs = [1]", "count(xs)"]))
)

row("canon.B0029", "{:a => 1}", diagnoses(["B0029"]), covers("rule:B0029"))

row("canon.B0029.writes", "{:a => 1}", formats(unlines(["{a: 1}"])))

row(
  "canon.B0030",
  join_lines(["def f", "  1", "end"]),
  diagnoses(["B0030"]),
  covers("rule:B0030")
)

row(
  "canon.B0030.writes",
  join_lines(["def f", "  1", "end"]),
  formats(unlines(["def f()", "  1", "end"]))
)

row("canon.B0031", "not(true)", diagnoses(["B0031"]), covers("rule:B0031"))

row("canon.B0031.writes", "not(true)", formats(unlines(["not true"])))

row("canon.B0031.list", "list(1, 2)", formats(unlines(["[1, 2]"])))

row("canon.B0032", "[1, 2,]", diagnoses(["B0032"]), covers("rule:B0032"))

row("canon.B0032.writes", "[1, 2,]", formats(unlines(["[1, 2]"])))

row("canon.B0033", "1000000", diagnoses(["B0033"]), covers("rule:B0033"))

row("canon.B0033.writes", "1000000", formats(unlines(["1_000_000"])))

row("canon.B0033.short", "65_535", formats(unlines(["65535"])))

row(
  "canon.B0034",
  join_lines(["a = 1", "b = 2", "not (a == b)"]),
  diagnoses(["B0034"]),
  covers("rule:B0034")
)

row(
  "canon.B0034.writes",
  join_lines(["a = 1", "b = 2", "not (a == b)"]),
  formats(unlines(["a = 1", "b = 2", "a != b"]))
)

row(
  "canon.B0035",
  join_lines(["a = true", "if a", "  1", "else", "  nil", "end"]),
  diagnoses(["B0035"]),
  covers("rule:B0035")
)

row(
  "canon.B0035.writes",
  join_lines(["a = true", "if a", "  1", "else", "  nil", "end"]),
  formats(unlines(["a = true", "", "if a", "  1", "end"]))
)

row(
  "canon.B0046",
  join_lines(["name = 1", "{name: name}"]),
  diagnoses(["B0046"]),
  covers("rule:B0046")
)

row(
  "canon.B0046.writes",
  join_lines(["name = 1", "size = 2", "{name: name, size: size, n: 3}"]),
  formats(unlines(["name = 1", "size = 2", "{name:, size:, n: 3}"]))
)

row(
  "canon.B0046.predicate",
  join_lines(["ok? = true", "{ok?: ok?}"]),
  formats(unlines(["ok? = true", "{ok?:}"]))
)

row(
  "canon.B0046.keeps",
  join_lines(["name = 1", "{name: 1, other: name}"]),
  formats(unlines(["name = 1", "{name: 1, other: name}"]))
)

row(
  "canon.B0047",
  join_lines(["name = 1", "name == nil"]),
  diagnoses(["B0047"]),
  covers("rule:B0047")
)

row(
  "canon.B0047.writes",
  join_lines(["name = 1", "name == nil"]),
  formats(unlines(["name = 1", "name.nil?"]))
)

row(
  "canon.B0047.reversed",
  join_lines(["name = 1", "nil == name"]),
  formats(unlines(["name = 1", "name.nil?"]))
)

row(
  "canon.B0047.call",
  join_lines(["name = 1", "nil?(name)"]),
  formats(unlines(["name = 1", "name.nil?"]))
)

row(
  "canon.B0047.keeps",
  join_lines(["name = 1", "name != nil"]),
  formats(unlines(["name = 1", "name != nil"]))
)

row("canon.B0065", "\"a\\nb\"", diagnoses(["B0065"]), covers("rule:B0065"))

row(
  "canon.B0066",
  join_lines(["m = {k: 1}", "get(m, :k)"]),
  diagnoses(["B0066"]),
  covers("rule:B0066")
)

row(
  "canon.B0066.writes",
  join_lines(["m = {k: 1}", "xs = [1]", "[get(m, :k), nth(0, xs)]"]),
  formats(unlines(["m = {k: 1}", "xs = [1]", "[m[:k], xs[0]]"]))
)

row(
  "canon.B0066.keeps",
  join_lines(["m = {k: 1}", "k = :k", "get(m, k)"]),
  formats(unlines(["m = {k: 1}", "k = :k", "get(m, k)"]))
)

row(
  "canon.B0066.eval",
  "[{k: 1}[:k], {k: 1}[:z], [1, 2][1], [1, 2][5], [[1, 2]][0][1]]",
  value("[1, nil, 2, nil, 2]")
)

row(
  "canon.B0065.writes",
  "\"a\\nb\"",
  formats(unlines(["join_lines(%w[a b])"]))
)

row(
  "canon.B0065.trailing",
  "\"done\\n\"",
  formats(unlines(["unlines([\"done\"])"]))
)

row("canon.B0065.alone", "\"\\n\"", formats(unlines(["line_break"])))

row("canon.B0065.keeps_tab", "\"a\\tb\"", formats(unlines(["\"a\\tb\""])))

row(
  "canon.B0065.eval",
  "[\"a\\nb\" == join_lines([\"a\", \"b\"]), \"a\\n\" == unlines([\"a\"]), \"\\n\" == line_break]",
  value("[true, true, true]")
)

row(
  "canon.B0047.eval",
  "[nil.nil?, 1.nil?, [].nil?, \"\".nil?, {a: 1}.nil?]",
  value("[true, false, false, false, false]"),
  covers("form:x == nil")
)

row(
  "canon.B0042",
  "apply(max, [1, 2])",
  diagnoses(["B0042"]),
  covers("rule:B0042")
)

row(
  "canon.B0042.writes",
  "apply(max, [1, 2])",
  formats(unlines(["max(*[1, 2])"]))
)

row(
  "canon.B0044",
  join_lines(
    [
      "def describe(v)",
      "  v",
      "end",
      "",
      "def go(vs)",
      "  map((v) -> describe(v), vs)",
      "end"
    ]
  ),
  diagnoses(["B0044"]),
  covers("rule:B0044")
)

row(
  "canon.B0044.writes",
  join_lines(
    [
      "def describe(v)",
      "  v",
      "end",
      "",
      "def go(vs)",
      "  map((v) -> describe(v), vs)",
      "end"
    ]
  ),
  formats(
    unlines(
      [
        "def describe(v)",
        "  v",
        "end",
        "",
        "def go(vs)",
        "  map(describe, vs)",
        "end"
      ]
    )
  )
)

row(
  "canon.B0044.keeps_a_different_call",
  join_lines(
    [
      "def two(a, b)",
      "  a + b",
      "end",
      "",
      "def go(vs)",
      "  map((v) -> two(v, 1), vs)",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "canon.B0045",
  join_lines(["def go(x)", "  to_s(to_s(x))", "end"]),
  diagnoses(["B0045"]),
  covers("rule:B0045")
)

row(
  "canon.B0045.writes",
  join_lines(["def go(x)", "  to_s(to_s(x))", "end"]),
  formats(unlines(["def go(x)", "  to_s(x)", "end"]))
)

row(
  "canon.B0045.keeps_a_lossy_chain",
  join_lines(["def go(x)", "  to_int(to_int(x))", "end"]),
  diagnoses([])
)

row("canon.B0024.one_line_fn", "f = fn(x) x end", diagnoses(["B0024"]))

row("canon.B0036", "car([1])", diagnoses(["B0036"]), covers("rule:B0036"))

row(
  "canon.B0037",
  "throw(error(:k, \"m\"))",
  diagnoses(["B0037"]),
  covers("rule:B0037")
)

row(
  "canon.B0038",
  join_lines(["begin", "  1", "rescue e", "  nil", "end"]),
  diagnoses(["B0038"]),
  covers("rule:B0038")
)

row(
  "canon.B0038.underscore_is_deliberate",
  join_lines(["begin", "  x = 1", "  x", "rescue _", "  nil", "end"]),
  diagnoses([])
)

row(
  "canon.B0039",
  join_lines(
    [
      "test \"a\"",
      "  assert true",
      "end",
      "",
      "test \"a\"",
      "  assert true",
      "end"
    ]
  ),
  diagnoses(["B0039"]),
  covers("rule:B0039")
)

row(
  "canon.B0040",
  join_lines(["def addOne(x)", "  x + 1", "end"]),
  diagnoses(["B0040"]),
  covers("rule:B0040")
)

row("canon.B0040.constant", "UART0 = 1", diagnoses([]))

row(
  "canon.B0041",
  join_lines(
    [
      "def getenv(_name, fallback)",
      "  fallback",
      "end",
      "",
      "def go()",
      "  1",
      "end",
      "",
      "if getenv(\"GO_MAIN\", \"\") == \"1\"",
      "  go",
      "end"
    ]
  ),
  diagnoses(["B0041"]),
  covers("rule:B0041")
)

row("ops.and", "true and false", value("false"), covers("op:and"))

row("ops.or", "false or 2", value("2"), covers("op:or"))

row(
  "ops.not",
  join_lines(["x = false", "not x"]),
  value("true"),
  covers("form:not x")
)

row(
  "errors.raise",
  "raise(:parse, \"bad row\")",
  fails(:eval, "parse: bad row"),
  covers("form:raise(:parse, \"bad row\")"),
  covers("builtin:raise")
)

row(
  "errors.raise.again",
  join_lines(
    [
      "e = raise(:k, \"m\") rescue nil",
      "begin",
      "  raise(:k, \"m\")",
      "rescue e",
      "  raise(e)",
      "end"
    ]
  ),
  fails(:eval, "k: m")
)

row(
  "errors.rescue.inline",
  join_lines(
    [
      "def risky(_x)",
      "  raise(:k, \"m\")",
      "end",
      "",
      "x = 1",
      "fallback = 2",
      "risky(x) rescue fallback"
    ]
  ),
  value("2"),
  covers("form:risky(x) rescue fallback"),
  covers("keyword:rescue")
)

row(
  "errors.rescue.kind",
  join_lines(
    [
      "begin",
      "  raise(:timeout, \"slow\")",
      "rescue :timeout as e",
      "  e.message",
      "end"
    ]
  ),
  value("\"slow\""),
  covers("keyword:begin"),
  covers(
    join_lines(
      ["form:begin", "  risky(x)", "rescue :timeout as e", "  wait(e)", "end"]
    )
  )
)

row(
  "errors.rescue.unmatched_kind_raises_again",
  join_lines(
    ["begin", "  raise(:refused, \"no\")", "rescue :timeout", "  1", "end"]
  ),
  fails(:eval, "refused: no")
)

row(
  "errors.rescue.catch_all_last",
  join_lines(
    [
      "begin",
      "  raise(:refused, \"no\")",
      "rescue :timeout",
      "  1",
      "rescue e",
      "  e.kind",
      "end"
    ]
  ),
  value(":refused")
)

row(
  "errors.ensure.runs_on_success",
  join_lines(
    [
      "log = [0]",
      "r = begin",
      "  1",
      "ensure",
      "  set!(log, [2])",
      "end",
      "[r, first(log)]"
    ]
  ),
  value("[1, 2]"),
  covers("keyword:ensure")
)

row(
  "errors.ensure.runs_on_failure",
  join_lines(
    [
      "log = [0]",
      "r = begin",
      "  begin",
      "    raise(:k, \"m\")",
      "  ensure",
      "    set!(log, [2])",
      "  end",
      "rescue :k",
      "  :caught",
      "end",
      "[r, first(log)]"
    ]
  ),
  value("[:caught, 2]")
)

row(
  "errors.def_rescue",
  join_lines(
    [
      "def f()",
      "  raise(:k, \"m\")",
      "rescue :k as e",
      "  e.kind",
      "end",
      "",
      "f"
    ]
  ),
  value(":k")
)

row(
  "errors.fields",
  join_lines(
    [
      "e = begin",
      "  raise(:k, \"m\", {data: {n: 1}, cause: raise(:inner, \"x\") rescue nil})",
      "rescue e",
      "  e",
      "end",
      "[e.kind, e.message, e.data, e.cause]"
    ]
  ),
  value("[:k, \"m\", {n: 1}, nil]")
)

row(
  "errors.cause",
  join_lines(
    [
      "inner = begin",
      "  raise(:inner, \"x\")",
      "rescue e",
      "  e",
      "end",
      "outer = begin",
      "  raise(:outer, \"y\", {cause: inner})",
      "rescue e",
      "  e",
      "end",
      "outer.cause.kind"
    ]
  ),
  value(":inner")
)

row(
  "errors.uncaught.cause_chain",
  join_lines(
    [
      "inner = begin",
      "  raise(:inner, \"x\")",
      "rescue e",
      "  e",
      "end",
      "raise(:outer, \"y\", {cause: inner})"
    ]
  ),
  fails(:eval, "caused by inner: x")
)

row(
  "records.field",
  join_lines(["cap = {status: 0}", "cap.status"]),
  value("0"),
  covers("form:cap.status")
)

row(
  "records.field.keyed_list",
  join_lines(["cap = [[:status, 3], [:stdout, \"\"]]", "cap.status"]),
  value("3")
)

row(
  "records.field.missing",
  join_lines(["cap = {status: 0}", "cap.stdout"]),
  fails(:eval, "no field `stdout`")
)

row(
  "calls.splat",
  join_lines(
    [
      "def f(a, b, c)",
      "  a + b + c",
      "end",
      "",
      "a = 1",
      "xs = [2, 3]",
      "f(a, *xs)"
    ]
  ),
  value("6"),
  covers("form:f(a, *xs)")
)

row(
  "programs.main",
  join_lines(["def main()", "  write_stdout(\"hi\")", "end"]),
  prints("hi")
)

row(
  "canon.B0043",
  join_lines(
    [
      "def ro_argv()",
      "  []",
      "end",
      "",
      "def ro_count()",
      "  0",
      "end",
      "",
      "def ro_check()",
      "  ro_count",
      "end"
    ]
  ),
  diagnoses(["B0043"]),
  covers("rule:B0043")
)
