# Unions: one line declares a closed set of records. Each arm is a record
# with everything a record gives; the union adds a predicate true for any
# arm, and a case over its arms that misses one and has no else is B0081.

row(
  "unions.declare",
  join_lines(
    [
      "union shape = circle(r: Float) | rect(w: Float, h: Float)",
      "rect(2.0, 3.0).h"
    ]
  ),
  value("3.0"),
  covers("form:union shape = circle(r: Float) | rect(w: Float, h: Float)")
)

row(
  "unions.construct_by_name",
  join_lines(
    ["union shape = circle(r) | rect(w, h)", "rect({h: 2, w: 1}) == rect(1, 2)"]
  ),
  value("true")
)

row(
  "unions.predicate",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "record point(x, y)",
      "[shape?(circle(1)), shape?(rect(1, 2)), shape?(point(1, 2)), shape?(1), circle?(rect(1, 2))]"
    ]
  ),
  value("[true, true, false, false, false]")
)

row(
  "unions.json",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "json_read(json_stringify([circle(1), rect(2, [3])])) == [circle(1), rect(2, [3])]"
    ]
  ),
  value("true")
)

row(
  "unions.arms_on_their_own_lines",
  join_lines(
    [
      "union shape =",
      "  circle(r)",
      "  | rect(w, h)",
      "  | tri(a, b, c)",
      "shape?(tri(1, 2, 3))"
    ]
  ),
  value("true")
)

row(
  "unions.exhaustive_case",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "def area(s)",
      "  case s",
      "  when circle?",
      "    3 * s.r * s.r",
      "  when rect?",
      "    s.w * s.h",
      "  end",
      "end",
      "[area(circle(2)), area(rect(2, 5))]"
    ]
  ),
  value("[12, 10]")
)

row(
  "unions.case_on_the_union_predicate",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "case rect(1, 2)",
      "when shape?",
      "  :shape",
      "end"
    ]
  ),
  value(":shape")
)

row(
  "unions.else_covers_the_rest",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "case rect(1, 2)",
      "when circle?",
      "  :round",
      "else",
      "  :other",
      "end"
    ]
  ),
  value(":other")
)

row(
  "check.B0081.else_suppresses",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "",
      "case rect(1, 2)",
      "when circle?",
      "  :round",
      "else",
      "  :other",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0081.exhaustive_passes",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "",
      "case rect(1, 2)",
      "when circle?",
      "  :round",
      "when rect?",
      "  :square",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0081",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "",
      "case rect(1, 2)",
      "when circle?",
      "  :round",
      "end"
    ]
  ),
  diagnoses(["B0081"]),
  covers("rule:B0081")
)

row(
  "check.B0081.stops_the_run",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h) | tri(a, b, c)",
      "def f(s)",
      "  case s",
      "  when circle?",
      "    1",
      "  end",
      "end",
      "f(circle(1))"
    ]
  ),
  fails(:check, "B0081")
)

row(
  "unions.formats_on_one_line",
  unlines(
    ["union shape =", "  circle(r: Float)", "  | rect(w: Float, h: Float)"]
  ),
  formats(
    unlines(["union shape = circle(r: Float) | rect(w: Float, h: Float)"])
  )
)

row(
  "unions.union_stays_a_free_name",
  join_lines(["def union(a, b)", "  append(a, b)", "end", "union([1], [2])"]),
  value("[1, 2]")
)

row(
  "unions.top_level_only",
  join_lines(["def f()", "  union shape = circle(r)", "end"]),
  fails(:parse, "top level")
)

row(
  "unions.arm_named_twice",
  "union shape = circle(r) | circle(d)",
  fails(:parse, "named twice")
)
