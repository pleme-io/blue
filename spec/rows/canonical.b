# One way to write each thing (docs/CANONICAL-FORMS.md): each rule's canonical
# rewrite, and the forms and words it writes.

row("canon.B0024", "x   =   1", diagnoses(["B0024"]), covers("rule:B0024"))

row("canon.B0024.writes", "x   =   1", formats("x = 1\n"))

row(
  "canon.B0025",
  "ready = true\nready && ready",
  diagnoses(["B0025"]),
  covers("rule:B0025")
)

row(
  "canon.B0025.writes",
  "true && false || !true",
  formats("true and false or not true\n")
)

row("canon.B0025.negation_as_operand", "!a == b", formats("(not a) == b\n"))

row(
  "canon.B0026",
  "unless false\n  1\nend",
  diagnoses(["B0026"]),
  covers("rule:B0026")
)

row(
  "canon.B0026.writes",
  "unless false\n  1\nend",
  formats("if not false\n  1\nend\n")
)

row(
  "canon.B0027",
  "a = 1\nif a == 1\n  1\nelse\n  if a == 2\n    2\n  end\nend",
  diagnoses(["B0027"]),
  covers("rule:B0027")
)

row(
  "canon.B0027.writes",
  "a = 1\nif a == 1\n  1\nelse\n  if a == 2\n    2\n  end\nend",
  formats("a = 1\n\nif a == 1\n  1\nelsif a == 2\n  2\nend\n")
)

row(
  "canon.B0028",
  "x = \"a\"\nx.concat(\"b\")",
  diagnoses(["B0028"]),
  covers("rule:B0028")
)

row(
  "canon.B0028.writes",
  "x = \"a\"\nx.concat(\"b\")",
  formats("x = \"a\"\nconcat(x, \"b\")\n")
)

row(
  "canon.B0028.pipe",
  "xs = [1]\nxs |> count",
  formats("xs = [1]\ncount(xs)\n")
)

row("canon.B0029", "{:a => 1}", diagnoses(["B0029"]), covers("rule:B0029"))

row("canon.B0029.writes", "{:a => 1}", formats("{a: 1}\n"))

row(
  "canon.B0030",
  "def f\n  1\nend",
  diagnoses(["B0030"]),
  covers("rule:B0030")
)

row("canon.B0030.writes", "def f\n  1\nend", formats("def f()\n  1\nend\n"))

row("canon.B0031", "not(true)", diagnoses(["B0031"]), covers("rule:B0031"))

row("canon.B0031.writes", "not(true)", formats("not true\n"))

row("canon.B0031.list", "list(1, 2)", formats("[1, 2]\n"))

row("canon.B0032", "[1, 2,]", diagnoses(["B0032"]), covers("rule:B0032"))

row("canon.B0032.writes", "[1, 2,]", formats("[1, 2]\n"))

row("canon.B0033", "1000000", diagnoses(["B0033"]), covers("rule:B0033"))

row("canon.B0033.writes", "1000000", formats("1_000_000\n"))

row("canon.B0033.short", "65_535", formats("65535\n"))

row(
  "canon.B0034",
  "a = 1\nb = 2\nnot (a == b)",
  diagnoses(["B0034"]),
  covers("rule:B0034")
)

row(
  "canon.B0034.writes",
  "a = 1\nb = 2\nnot (a == b)",
  formats("a = 1\nb = 2\na != b\n")
)

row(
  "canon.B0035",
  "a = true\nif a\n  1\nelse\n  nil\nend",
  diagnoses(["B0035"]),
  covers("rule:B0035")
)

row(
  "canon.B0035.writes",
  "a = true\nif a\n  1\nelse\n  nil\nend",
  formats("a = true\n\nif a\n  1\nend\n")
)

row(
  "canon.B0042",
  "apply(max, [1, 2])",
  diagnoses(["B0042"]),
  covers("rule:B0042")
)

row("canon.B0042.writes", "apply(max, [1, 2])", formats("max(*[1, 2])\n"))

row(
  "canon.B0044",
  "def describe(v)\n  v\nend\n\ndef go(vs)\n  map((v) -> describe(v), vs)\nend",
  diagnoses(["B0044"]),
  covers("rule:B0044")
)

row(
  "canon.B0044.writes",
  "def describe(v)\n  v\nend\n\ndef go(vs)\n  map((v) -> describe(v), vs)\nend",
  formats("def describe(v)\n  v\nend\n\ndef go(vs)\n  map(describe, vs)\nend\n")
)

row(
  "canon.B0044.keeps_a_different_call",
  "def two(a, b)\n  a + b\nend\n\ndef go(vs)\n  map((v) -> two(v, 1), vs)\nend",
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
  "begin\n  1\nrescue e\n  nil\nend",
  diagnoses(["B0038"]),
  covers("rule:B0038")
)

row(
  "canon.B0038.underscore_is_deliberate",
  "begin\n  x = 1\n  x\nrescue _\n  nil\nend",
  diagnoses([])
)

row(
  "canon.B0039",
  "test \"a\"\n  assert true\nend\n\ntest \"a\"\n  assert true\nend",
  diagnoses(["B0039"]),
  covers("rule:B0039")
)

row(
  "canon.B0040",
  "def addOne(x)\n  x + 1\nend",
  diagnoses(["B0040"]),
  covers("rule:B0040")
)

row("canon.B0040.constant", "UART0 = 1", diagnoses([]))

row(
  "canon.B0041",
  "def getenv(_name, fallback)\n  fallback\nend\n\ndef go()\n  1\nend\n\nif getenv(\"GO_MAIN\", \"\") == \"1\"\n  go\nend",
  diagnoses(["B0041"]),
  covers("rule:B0041")
)

row("ops.and", "true and false", value("false"), covers("op:and"))

row("ops.or", "false or 2", value("2"), covers("op:or"))

row("ops.not", "x = false\nnot x", value("true"), covers("form:not x"))

row(
  "errors.raise",
  "raise(:parse, \"bad row\")",
  fails(:eval, "parse: bad row"),
  covers("form:raise(:parse, \"bad row\")"),
  covers("builtin:raise")
)

row(
  "errors.raise.again",
  "e = raise(:k, \"m\") rescue nil\nbegin\n  raise(:k, \"m\")\nrescue e\n  raise(e)\nend",
  fails(:eval, "k: m")
)

row(
  "errors.rescue.inline",
  "def risky(_x)\n  raise(:k, \"m\")\nend\n\nx = 1\nfallback = 2\nrisky(x) rescue fallback",
  value("2"),
  covers("form:risky(x) rescue fallback"),
  covers("keyword:rescue")
)

row(
  "errors.rescue.kind",
  "begin\n  raise(:timeout, \"slow\")\nrescue :timeout as e\n  e.message\nend",
  value("\"slow\""),
  covers("keyword:begin"),
  covers("form:begin\n  risky(x)\nrescue :timeout as e\n  wait(e)\nend")
)

row(
  "errors.rescue.unmatched_kind_raises_again",
  "begin\n  raise(:refused, \"no\")\nrescue :timeout\n  1\nend",
  fails(:eval, "refused: no")
)

row(
  "errors.rescue.catch_all_last",
  "begin\n  raise(:refused, \"no\")\nrescue :timeout\n  1\nrescue e\n  e.kind\nend",
  value(":refused")
)

row(
  "errors.ensure.runs_on_success",
  "log = [0]\nr = begin\n  1\nensure\n  set!(log, [2])\nend\n[r, first(log)]",
  value("[1, 2]"),
  covers("keyword:ensure")
)

row(
  "errors.ensure.runs_on_failure",
  "log = [0]\nr = begin\n  begin\n    raise(:k, \"m\")\n  ensure\n    set!(log, [2])\n  end\nrescue :k\n  :caught\nend\n[r, first(log)]",
  value("[:caught, 2]")
)

row(
  "errors.def_rescue",
  "def f()\n  raise(:k, \"m\")\nrescue :k as e\n  e.kind\nend\n\nf",
  value(":k")
)

row(
  "errors.fields",
  "e = begin\n  raise(:k, \"m\", {data: {n: 1}, cause: raise(:inner, \"x\") rescue nil})\nrescue e\n  e\nend\n[e.kind, e.message, e.data, e.cause]",
  value("[:k, \"m\", {n: 1}, nil]")
)

row(
  "errors.cause",
  "inner = begin\n  raise(:inner, \"x\")\nrescue e\n  e\nend\nouter = begin\n  raise(:outer, \"y\", {cause: inner})\nrescue e\n  e\nend\nouter.cause.kind",
  value(":inner")
)

row(
  "errors.uncaught.cause_chain",
  "inner = begin\n  raise(:inner, \"x\")\nrescue e\n  e\nend\nraise(:outer, \"y\", {cause: inner})",
  fails(:eval, "caused by inner: x")
)

row(
  "records.field",
  "cap = {status: 0}\ncap.status",
  value("0"),
  covers("form:cap.status")
)

row(
  "records.field.keyed_list",
  "cap = [[:status, 3], [:stdout, \"\"]]\ncap.status",
  value("3")
)

row(
  "records.field.missing",
  "cap = {status: 0}\ncap.stdout",
  fails(:eval, "no field `stdout`")
)

row(
  "calls.splat",
  "def f(a, b, c)\n  a + b + c\nend\n\na = 1\nxs = [2, 3]\nf(a, *xs)",
  value("6"),
  covers("form:f(a, *xs)")
)

row("programs.main", "def main()\n  write_stdout(\"hi\")\nend", prints("hi"))

row(
  "canon.B0043",
  "def ro_argv()\n  []\nend\n\ndef ro_count()\n  0\nend\n\ndef ro_check()\n  ro_count\nend",
  diagnoses(["B0043"]),
  covers("rule:B0043")
)
