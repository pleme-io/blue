# The test harness's surface: a test's declaration (the controls it
# satisfies, the definition it targets) and the breach assertion. What a test
# run does with them is `blue test`'s, which no evaluator column runs: the
# harness's own tests and crates/blue-lang-cli/tests/compliance.rs hold it.

row(
  "testing.declaration.ignored_by_run",
  join_lines(
    [
      "def parse(x)",
      "  x",
      "end",
      "",
      "test \"isolated\", {satisfies: [:nist_ac_6], target: parse}",
      "  assert true",
      "end",
      "",
      ":ran"
    ]
  ),
  value(":ran"),
  covers(
    join_lines(
      [
        "form:test \"isolated\", {satisfies: [:nist_ac_6], target: parse}",
        "  assert parse(1)",
        "end"
      ]
    )
  )
)

row(
  "testing.declaration.order",
  join_lines(
    ["test \"t\", {satisfies: %i[nist_cm_7 nist_ac_6]}", "  assert true", "end"]
  ),
  diagnoses(["B0068"]),
  covers("rule:B0068")
)

row(
  "testing.declaration.order.writes",
  join_lines(
    [
      "def f(x)",
      "  x",
      "end",
      "",
      "test \"t\", {target: f, satisfies: %i[nist_cm_7 nist_ac_6]}",
      "  assert f(1) == 1",
      "end"
    ]
  ),
  formats(
    unlines(
      [
        "def f(x)",
        "  x",
        "end",
        "",
        "test \"t\", {satisfies: %i[nist_ac_6 nist_cm_7], target: f}",
        "  assert f(1) == 1",
        "end"
      ]
    )
  )
)

row(
  "testing.declaration.long_header_breaks",
  join_lines(
    [
      "def parse_token(x)",
      "  x",
      "end",
      "",
      "test \"a declaration too long for one line\", {satisfies: [:nist_ac_6], target: parse_token}",
      "  assert true",
      "end"
    ]
  ),
  formats(
    unlines(
      [
        "def parse_token(x)",
        "  x",
        "end",
        "",
        "test \"a declaration too long for one line\", {",
        "  satisfies: [:nist_ac_6],",
        "  target: parse_token",
        "}",
        "  assert true",
        "end"
      ]
    )
  )
)

row(
  "testing.declaration.unknown_control",
  join_lines(["test \"t\", {satisfies: [:nist_zz_1]}", "  assert true", "end"]),
  diagnoses(["B0069"]),
  covers("rule:B0069")
)

row(
  "testing.declaration.target_is_a_builtin",
  join_lines(["test \"t\", {target: read_file}", "  assert true", "end"]),
  diagnoses(["B0069"])
)

row(
  "testing.declaration.target_is_unbound",
  join_lines(["test \"t\", {target: parse_tokn}", "  assert true", "end"]),
  diagnoses(["B0001"])
)

row(
  "testing.declaration.unknown_key",
  join_lines(["test \"t\", {tags: [:slow]}", "  assert true", "end"]),
  fails(
    :parse,
    "a test declares `satisfies:`, `target:`, `kind:`, `allow:` and `fakes:`"
  )
)

row(
  "testing.declaration.control_twice",
  join_lines(
    ["test \"t\", {satisfies: %i[nist_ac_6 nist_ac_6]}", "  assert true", "end"]
  ),
  fails(:parse, "is listed twice")
)

row(
  "testing.declaration.target_is_a_name",
  join_lines(["test \"t\", {target: \"parse\"}", "  assert true", "end"]),
  fails(:parse, "`target:` names the definition the test verifies")
)

row(
  "testing.assert_panics.formats",
  join_lines(["test \"t\"", "  assert_panics(read_file(\"x\"))", "end"]),
  formats(unlines(["test \"t\"", "  assert_panics read_file(\"x\")", "end"])),
  covers("keyword:assert_panics")
)

row(
  "testing.assert_panics.ignored_by_run",
  join_lines(
    [
      "test \"t\"",
      "  assert_panics read_file(\"/etc/hosts\")",
      "end",
      "",
      ":ran"
    ]
  ),
  value(":ran")
)

row(
  "testing.B0083",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi asks the machine.",
      "",
      "    1 + 1 #=> 2",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi runs `date`.",
      "",
      "    1 + 1 #=> 2",
      "\"\"\"",
      "def kagi()",
      "  exec_capture(\"date\")",
      "end"
    ]
  ),
  diagnoses(%w[B0083 B0090]),
  covers("rule:B0083"),
  bidama("kagi")
)

row(
  "testing.B0083.discharged_by_an_integration_test",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi asks the machine.",
      "",
      "    1 + 1 #=> 2",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi runs `date`.",
      "",
      "    1 + 1 #=> 2",
      "\"\"\"",
      "def kagi()",
      "  exec_capture(\"date\")",
      "end",
      "",
      "test \"kagi\", {kind: :integration, allow: [:process]}",
      "  assert kagi != nil",
      "end"
    ]
  ),
  diagnoses([]),
  bidama("kagi")
)

row(
  "testing.B0084",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi asks hito for the date.",
      "",
      "    1 + 1 #=> 2",
      "\"\"\"",
      "",
      "use(\"sp_seam\", [:sp_ask])",
      "",
      "@doc \"\"\"",
      "kagi answers what sp_seam asked.",
      "",
      "    1 + 1 #=> 2",
      "\"\"\"",
      "def kagi()",
      "  sp_ask",
      "end"
    ]
  ),
  diagnoses(%w[B0084 B0090]),
  covers("rule:B0084"),
  bidama("kagi")
)

row(
  "testing.B0085",
  unlines(
    [
      "def main()",
      "  write_file(getenv(\"GEN_OUT\", \"out.txt\"), \"x\")",
      "end"
    ]
  ),
  diagnoses(["B0085"]),
  covers("rule:B0085"),
  role("generator")
)

row(
  "testing.B0086",
  unlines(["def main()", "  1", "end"]),
  diagnoses(["B0086"]),
  covers("rule:B0086"),
  role("service")
)

row(
  "testing.B0087",
  unlines(
    [
      "def main()",
      "  1",
      "end",
      "",
      "test \"serves\", {kind: :e2e}",
      "  assert main == 1",
      "end"
    ]
  ),
  diagnoses(["B0087"]),
  covers("rule:B0087"),
  role("binding")
)

row(
  "testing.B0088",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is one.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end",
      "",
      "test \"kagi runs\"",
      "  kagi",
      "end"
    ]
  ),
  diagnoses(["B0088"]),
  covers("rule:B0088"),
  bidama("kagi")
)

row(
  "testing.B0089",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is one.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end",
      "",
      "test \"kagi\"",
      "  one = kagi",
      "  assert one == one",
      "end"
    ]
  ),
  diagnoses(["B0089"]),
  covers("rule:B0089"),
  bidama("kagi")
)

row(
  "testing.B0090",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is one.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end"
    ]
  ),
  diagnoses(["B0090"]),
  covers("rule:B0090"),
  bidama("kagi")
)

row(
  "testing.B0091",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi refuses a negative.",
      "",
      "    kagi(1) #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi gives back a count.",
      "",
      "    kagi(1) #=> 1",
      "\"\"\"",
      "def kagi(n)",
      "  if n < 0",
      "    raise(:negative, \"no\")",
      "  end",
      "  n",
      "end",
      "",
      "test \"kagi\"",
      "  assert kagi(2) == 2",
      "end"
    ]
  ),
  diagnoses(["B0091"]),
  covers("rule:B0091"),
  bidama("kagi")
)

row(
  "testing.B0092",
  unlines(
    [
      "def gate()",
      "  1",
      "end",
      "",
      "test \"gate\"",
      "  assert gate == 1",
      "end"
    ]
  ),
  diagnoses(["B0092"]),
  covers("rule:B0092"),
  role("gate")
)

row(
  "testing.B0092.staged",
  unlines(
    [
      "def gate()",
      "  1",
      "end",
      "",
      "test \"gate\"",
      "  assert gate == 1",
      "end"
    ]
  ),
  diagnoses([]),
  role("staged-gate")
)

row(
  "testing.B0093",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi(1) #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is its argument.",
      "",
      "    kagi(1) #=> 1",
      "\"\"\"",
      "def kagi(a)",
      "  a",
      "end",
      "",
      "test \"kagi\"",
      "  assert kagi(1) == 1",
      "  xs = [1, 2]",
      "  assert xs == [1, 2]",
      "end"
    ]
  ),
  diagnoses(["B0093"]),
  covers("rule:B0093"),
  bidama("kagi")
)

row(
  "testing.B0094",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    circle(1).r #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "shape is a circle or a square.",
      "",
      "    circle(1).r #=> 1",
      "\"\"\"",
      "union shape = circle(r) | square(s)",
      "",
      "test \"kagi\"",
      "  assert circle(1).r == 1",
      "end"
    ]
  ),
  diagnoses(%w[B0090 B0090 B0094]),
  covers("rule:B0094"),
  bidama("kagi")
)

row(
  "testing.B0095",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi(1) #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is its argument.",
      "",
      "    kagi(1) #=> 1",
      "\"\"\"",
      "def kagi(a, b?)",
      "  if b.nil?",
      "    a",
      "  else",
      "    a + b",
      "  end",
      "end",
      "",
      "test \"kagi\"",
      "  assert kagi(1) == 1",
      "end"
    ]
  ),
  diagnoses(["B0095"]),
  covers("rule:B0095"),
  bidama("kagi")
)

row(
  "testing.B0096",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi({enabled: true}) #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi runs when enabled.",
      "",
      "    kagi({enabled: true}) #=> 1",
      "\"\"\"",
      "def kagi(cfg)",
      "  if cfg[:enabled]",
      "    1",
      "  else",
      "    0",
      "  end",
      "end",
      "",
      "test \"kagi\"",
      "  assert kagi({enabled: true}) == 1",
      "end"
    ]
  ),
  diagnoses(["B0096"]),
  covers("rule:B0096"),
  bidama("kagi")
)

row(
  "testing.B0097",
  unlines(
    [
      "@moduledoc \"\"\"",
      "kagi holds one value.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "",
      "@doc \"\"\"",
      "kagi is one.",
      "",
      "    kagi #=> 1",
      "\"\"\"",
      "def kagi()",
      "  1",
      "end",
      "",
      "test \"kagi\", {fakes: [:valkey]}",
      "  assert kagi == 1",
      "end"
    ]
  ),
  diagnoses(["B0097"]),
  covers("rule:B0097"),
  bidama("kagi")
)
