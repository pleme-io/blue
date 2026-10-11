# Strings and keywords (okite D0013): two different values, which the builtins
# that read a name as text take alike. These rows are the proof B0023 stands
# on: its fix is machine-applicable exactly where a row here shows the string
# and the keyword give the same result, and nowhere else.

row(
  "keywords.not_a_string",
  "[\"a\" == :a, {\"a\" => 1} == {a: 1}, get({a: 1}, \"a\")]",
  value("[false, false, nil]"),
  covers("okite:D0013")
)

row(
  "keywords.error_kind.string",
  "throw(error(\"bad\", \"why\"))",
  fails(:eval, "#<error :bad \"why\">")
)

row(
  "keywords.error_kind.keyword",
  "throw(error(:bad, \"why\"))",
  fails(:eval, "#<error :bad \"why\">")
)

row(
  "keywords.json_get",
  "d = json_parse(\"{\\\"a\\\": 1}\")\n[json_get(d, \"a\"), json_get(d, :a)]",
  value("[1, 1]")
)

row(
  "keywords.json_get_or",
  "d = json_parse(\"{\\\"a\\\": 1}\")\n[json_get_or(d, \"a\", 0), json_get_or(d, :a, 0), json_get_or(d, \"b\", 0), json_get_or(d, :b, 0)]",
  value("[1, 1, 0, 0]")
)

row(
  "keywords.B0023.machine",
  "error(\"bad\", \"why\")",
  diagnoses(["B0023"]),
  covers("rule:B0023")
)

row("keywords.B0023.map_key", "{\"k\" => 1}", diagnoses(["B0023"]))

row(
  "keywords.B0023.not_a_name",
  "[json_get(json_parse(\"{}\"), \"a-b\"), {\"x y\" => 1}]",
  diagnoses([])
)

row(
  "keywords.B0023.text_is_not_reported",
  "[concat(\"done\", \"!\"), {k: \"v\"}, \"a\" == \"b\"]",
  diagnoses([])
)

row(
  "keywords.B0023.own_definition",
  "def json_get(d, k)\n  [d, k]\nend\n\njson_get(1, \"a\")",
  diagnoses([])
)

row(
  "keywords.B0023.own_definition_differs",
  "def json_get(d, k)\n  [d, k]\nend\n\n[json_get(1, \"a\"), json_get(1, :a)]",
  value("[[1, \"a\"], [1, :a]]")
)

row(
  "keywords.B0023.local",
  "def f(json_get)\n  json_get(1, \"a\")\nend",
  diagnoses([])
)
