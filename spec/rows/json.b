# JSON: parse, stringify and the pair-list reading of an object. An object
# that decodes to a map, so that a value round-trips, is the destination (G12).

row(
  "json.parse.number",
  "json_parse(\"42\")",
  value("42"),
  covers("builtin:json_parse")
)

row(
  "json.parse.array",
  "json_parse(\"[1, \\\"a\\\", null, true]\")",
  value("[1, \"a\", nil, true]")
)

row(
  "json.parse.object",
  "json_parse(\"{\\\"a\\\": 1}\")",
  value("[[\"a\", 1]]")
)

row("json.parse.bad", "json_parse(\"{\")", fails(:eval, "EOF while parsing"))

row(
  "json.stringify",
  "json_stringify([1, \"a\", nil])",
  value("\"[1,\\\"a\\\",null]\""),
  covers("builtin:json_stringify")
)

row("json.stringify.map", "json_stringify({a: 1})", value("\"{\\\"a\\\":1}\""))

row(
  "json.get",
  "json_get(json_parse(\"{\\\"a\\\": 1}\"), \"a\")",
  value("1"),
  covers("builtin:json_get")
)

row(
  "json.get_or",
  "json_get_or(json_parse(\"{}\"), \"a\", 0)",
  value("0"),
  covers("builtin:json_get_or")
)

row(
  "json.roundtrip",
  "json_parse(json_stringify({a: 1})) == {a: 1}",
  value("true"),
  pending("G12")
)

row(
  "json.error_value",
  "json_stringify(error(:boom, \"why\")) != \"null\"",
  value("true"),
  pending("G4")
)
