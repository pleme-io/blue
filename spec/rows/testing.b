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
  fails(:parse, "a test declares `satisfies:` and `target:`")
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
