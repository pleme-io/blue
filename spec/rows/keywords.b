row(
  "keywords.not_a_string",
  "[\"a\" == :a, {\"a\" => 1} == {a: 1}, get({a: 1}, \"a\")]",
  value("[false, false, nil]"),
  covers("okite:D0015")
)

row(
  "keywords.error_kind",
  join_lines(
    ["k = \"bad\"", "[error(k, \"why\").kind, error(:bad, \"why\").kind]"]
  ),
  value("[:bad, :bad]")
)

row(
  "keywords.json_get",
  join_lines(
    [
      "d = json_parse(\"{\\\"a\\\": 1}\")",
      "k = \"a\"",
      "[json_get(d, k), json_get(d, :a)]"
    ]
  ),
  value("[1, 1]")
)

row(
  "keywords.json_get_or",
  join_lines(
    [
      "d = json_parse(\"{\\\"a\\\": 1}\")",
      "k = \"a\"",
      "m = \"b\"",
      "[json_get_or(d, k, 0), json_get_or(d, :a, 0), json_get_or(d, m, 0), json_get_or(d, :b, 0)]"
    ]
  ),
  value("[1, 1, 0, 0]")
)

row(
  "keywords.B0067.machine",
  "error(\"bad\", \"why\")",
  diagnoses(["B0067"]),
  covers("rule:B0067")
)

row(
  "keywords.B0067.respelled",
  join_lines(["d = json_parse(\"{}\")", "json_get_or(d, \"a\", 0)"]),
  formats(join_lines(["d = json_parse(\"{}\")", "json_get_or(d, :a, 0)"]))
)

row(
  "keywords.B0067.not_a_name",
  "json_get(json_parse(\"{}\"), \"a-b\")",
  diagnoses([])
)

row(
  "keywords.B0067.map_keys_and_text",
  "[concat(\"done\", \"!\"), {\"k\" => 1}, \"a\" == \"b\"]",
  diagnoses([])
)

row(
  "keywords.B0067.own_definition",
  join_lines(
    ["def json_get(d, k)", "  [d, k]", "end", "", "json_get(1, \"a\")"]
  ),
  diagnoses([])
)

row(
  "keywords.B0067.own_definition_differs",
  join_lines(
    [
      "def json_get(d, k)",
      "  [d, k]",
      "end",
      "",
      "[json_get(1, \"a\"), json_get(1, :a)]"
    ]
  ),
  value("[[1, \"a\"], [1, :a]]")
)

row(
  "keywords.B0067.local",
  join_lines(["def f(json_get)", "  json_get(1, \"a\")", "end"]),
  diagnoses([])
)
