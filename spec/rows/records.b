# Records: one line declares a constructor, a predicate and the dot reads a
# field. A record is a map carrying its name (okite D0017).

row(
  "records.declare",
  join_lines(["record point(x, y: Int)", "point(1, 2).y"]),
  value("2"),
  covers("form:record point(x, y: Int)")
)

row(
  "records.by_name",
  join_lines(["record point(x, y)", "point({y: 2, x: 1}) == point(1, 2)"]),
  value("true")
)

row(
  "records.predicate",
  join_lines(
    [
      "record point(x, y)",
      "record spot(x, y)",
      "[point?(point(1, 2)), spot?(point(1, 2)), point?({x: 1, y: 2})]"
    ]
  ),
  value("[true, false, false]")
)

row(
  "records.update",
  join_lines(
    ["record point(x, y)", "p = point(1, 2)", "[point(**p, x: 9), p]"]
  ),
  value("[point({x: 9, y: 2}), point({x: 1, y: 2})]")
)

row(
  "records.equality_includes_the_name",
  join_lines(
    ["record point(x, y)", "record spot(x, y)", "point(1, 2) == spot(1, 2)"]
  ),
  value("false"),
  covers("okite:D0017")
)

row(
  "records.nest",
  join_lines(
    [
      "record point(x, y)",
      "record seg(a: point, b: point)",
      "seg(point(1, 2), point(3, 4)).b.y"
    ]
  ),
  value("4")
)

row(
  "records.json",
  join_lines(
    [
      "record point(x, y)",
      "json_read(json_stringify(point(1, [2]))) == point(1, [2])"
    ]
  ),
  value("true")
)

row(
  "records.case",
  join_lines(
    [
      "record point(x, y)",
      "case point(1, 2)",
      "when point?",
      "  :yes",
      "else",
      "  :no",
      "end"
    ]
  ),
  value(":yes")
)

row(
  "records.record_name",
  join_lines(
    ["record point(x, y)", "[record_name(point(1, 2)), record_name(1)]"]
  ),
  value("[\"point\", nil]"),
  covers("builtin:record_name")
)

row(
  "records.record_fields",
  join_lines(["record point(x, y)", "record_fields(point(1, 2))"]),
  value("{x: 1, y: 2}"),
  covers("builtin:record_fields")
)

row(
  "records.keys_stop_matching_is_a_plain_map",
  join_lines(
    [
      "record point(x, y)",
      "[record_name(assoc(point(1, 2), :z, 3)), record_name(assoc(point(1, 2), :x, 9))]"
    ]
  ),
  value("[nil, \"point\"]")
)

row(
  "records.run_time_door",
  join_lines(["record point(x, y)", "f = point", "f(1)"]),
  fails(:eval, "takes 2 fields")
)

row(
  "records.struct_names_record",
  "struct Point",
  fails(:parse, "record point(x, y)")
)

row(
  "check.B0079",
  join_lines(["record point(x, y)", "point(1)"]),
  diagnoses(["B0079"]),
  covers("rule:B0079")
)

row(
  "check.B0079.stops_the_run",
  join_lines(["record point(x, y)", "point({x: 1, z: 2})"]),
  fails(:check, "B0079")
)
