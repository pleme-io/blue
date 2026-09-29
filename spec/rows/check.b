# The check stage: one row per rule in blue_lang_check::RULES (B0001-B0009),
# observed by `blue check` and in-process, plus the run door refusing an
# error-severity finding before anything runs, and the one escape hatch.

row(
  "check.B0001",
  "def f(xs)\n  lenght(xs)\nend",
  diagnoses(["B0001"]),
  covers("rule:B0001")
)

row(
  "check.B0001.run_refuses",
  "write_stdout(\"side effect\")\nnope()",
  fails(:check, "B0001"),
  covers("rule:B0001")
)

row(
  "check.B0002",
  "def f(x)\n  y = x + 1\n  x\nend",
  diagnoses(["B0002"]),
  covers("rule:B0002")
)

row("check.B0002.underscore", "def f(x)\n  _y = x + 1\n  x\nend", diagnoses([]))
row("check.B0002.runs", "def f(x)\n  y = x + 1\n  x\nend\n\nf(1)", value("1"))

row(
  "check.B0003",
  "def f(a: Int) -> Str\n  a + 1\nend",
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.B0004",
  "def f(s: Str) -> Int\n  s + 1\nend",
  diagnoses(["B0004"]),
  covers("rule:B0004")
)

row(
  "check.B0005",
  "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\ndef g() -> Int\n  add(1, \"two\")\nend",
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row("check.B0006", "def f(\n", diagnoses(["B0006"]), covers("rule:B0006"))

row(
  "check.B0007",
  "# waive B0001\ndef f()\n  1\nend",
  diagnoses(["B0007"]),
  covers("rule:B0007")
)

row(
  "check.B0008",
  "# waive B0001: nothing here is unbound\ndef f()\n  1\nend",
  diagnoses(["B0008"]),
  covers("rule:B0008")
)

row(
  "check.B0009",
  "use(\"sp_amb_a\")\nuse(\"sp_amb_b\")\n\nsp_amb()",
  diagnoses(["B0009"]),
  covers("rule:B0009")
)

row(
  "check.B0009.run_refuses",
  "use(\"sp_amb_a\")\nuse(\"sp_amb_b\")\n\nsp_amb()",
  fails(:check, "B0009"),
  covers("rule:B0009"),
  pending("G16", "wasm")
)

row(
  "check.waiver",
  "# waive B0001: the fixture needs a raise at runtime\ndef f()\n  nope()\nend",
  diagnoses([])
)

row(
  "check.waiver.runs",
  "# waive B0001: the fixture needs a raise at runtime\ndef f()\n  nope()\nend\n\nf()",
  fails(:eval, "nope"),
  pending("G19", "vm")
)

row(
  "check.every_error_in_one_pass",
  "def f()\n  a1()\nend\n\ndef g()\n  a2()\nend",
  diagnoses(["B0001", "B0001"])
)

row(
  "check.unknown_type_name",
  "def f(n: Itn) -> Int\n  1\nend",
  diagnoses(["B0010"]),
  pending("G8")
)

row(
  "check.test_blocks_checked",
  "test \"t\"\n  assert nope() == 1\nend",
  diagnoses(["B0001"])
)

row(
  "check.B0010",
  "def f(xs)\n  sp_mod::sp_twice(xs)\nend",
  diagnoses(["B0010"]),
  covers("rule:B0010")
)

row(
  "check.B0011",
  "use(\"sp_mod\")\n\nsp_mod::sp_twicf(1)",
  diagnoses(["B0011"]),
  covers("rule:B0011")
)
