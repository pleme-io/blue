# Patterns: a `when` destructures a record by position, a list by head and
# rest, a map by key. A name in a pattern binds, `_` matches anything, a
# literal compares with ==.

row(
  "patterns.record_by_position",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "def area(s)",
      "  case s",
      "  when circle(r)",
      "    3 * r * r",
      "  when rect(w, h)",
      "    w * h",
      "  end",
      "end",
      "[area(circle(2)), area(rect(2, 5))]"
    ]
  ),
  value("[12, 10]"),
  covers(
    join_lines(
      [
        "form:case s",
        "when rect(w, h)",
        "  w * h",
        "when [x, *rest]",
        "  rest",
        "when {name:}",
        "  name",
        "end"
      ]
    )
  )
)

row(
  "patterns.record_of_a_plain_record",
  join_lines(
    [
      "record point(x, y)",
      "case point(3, 4)",
      "when point(a, b)",
      "  a - b",
      "end"
    ]
  ),
  value("-1")
)

row(
  "patterns.record_literal_field_refines",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "def kind(s)",
      "  case s",
      "  when rect(w, 1)",
      "    [:strip, w]",
      "  when rect(_, _)",
      "    :box",
      "  else",
      "    :other",
      "  end",
      "end",
      "[kind(rect(4, 1)), kind(rect(4, 2)), kind(circle(1))]"
    ]
  ),
  value("[[:strip, 4], :box, :other]")
)

row(
  "patterns.list_head_and_rest",
  join_lines(
    [
      "def split(xs)",
      "  case xs",
      "  when [x, *rest]",
      "    [x, rest]",
      "  else",
      "    :empty",
      "  end",
      "end",
      "[split([1, 2, 3]), split([1]), split([]), split(\"ab\")]"
    ]
  ),
  value("[[1, [2, 3]], [1, []], :empty, :empty]")
)

row(
  "patterns.list_exact_length",
  join_lines(
    [
      "def pair(xs)",
      "  case xs",
      "  when [a, b]",
      "    a + b",
      "  else",
      "    :no",
      "  end",
      "end",
      "[pair([1, 2]), pair([1, 2, 3]), pair([1])]"
    ]
  ),
  value("[3, :no, :no]")
)

row(
  "patterns.list_literal_elements",
  join_lines(
    [
      "def tag(xs)",
      "  case xs",
      "  when [:ok, v]",
      "    v",
      "  when [:no, *_]",
      "    :refused",
      "  end",
      "end",
      "[tag([:ok, 5]), tag([:no, 1, 2]), tag([:maybe, 1])]"
    ]
  ),
  value("[5, :refused, nil]")
)

row(
  "patterns.map_by_key",
  join_lines(
    [
      "def named(m)",
      "  case m",
      "  when {name:}",
      "    name",
      "  else",
      "    :anonymous",
      "  end",
      "end",
      "[named({name: \"a\", age: 3}), named({age: 3}), named(7)]"
    ]
  ),
  value("[\"a\", :anonymous, :anonymous]")
)

row(
  "patterns.map_key_and_value",
  join_lines(
    [
      "def read(r)",
      "  case r",
      "  when {ok: true, value: v}",
      "    v",
      "  when {ok: false, refusal: _}",
      "    :refused",
      "  end",
      "end",
      "[read({ok: true, value: 2}), read({ok: false, refusal: 1})]"
    ]
  ),
  value("[2, :refused]")
)

row(
  "patterns.a_map_without_a_name_compares_whole",
  join_lines(
    [
      "case {ok: false, refusal: 1}",
      "when {ok: false}",
      "  :part",
      "else",
      "  :whole",
      "end"
    ]
  ),
  value(":whole")
)

row(
  "patterns.map_reads_a_record",
  join_lines(
    ["record point(x, y)", "case point(3, 4)", "when {y:}", "  y", "end"]
  ),
  value("4")
)

row(
  "patterns.nested",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "case [rect(2, 3), {tag: [:a, :b]}]",
      "when [rect(w, _), {tag: [_, t]}]",
      "  [w, t]",
      "end"
    ]
  ),
  value("[2, :b]")
)

row(
  "patterns.a_name_binds_fresh",
  join_lines(["x = 10", "case [1]", "when [x]", "  x", "end"]),
  value("1")
)

row(
  "patterns.without_a_name_compares",
  join_lines(["case [1, 2]", "when [1, 2]", "  :same", "end"]),
  value(":same")
)

row(
  "patterns.return_inside_an_arm",
  join_lines(
    [
      "def first_big(xs)",
      "  case xs",
      "  when [x, *_]",
      "    if x > 1",
      "      return x",
      "    end",
      "  end",
      "  :small",
      "end",
      "[first_big([5, 1]), first_big([1]), first_big([])]"
    ]
  ),
  value("[5, :small, :small]")
)

row(
  "patterns.binds_a_name_twice",
  join_lines(["case [1, 1]", "when [x, x]", "  x", "end"]),
  fails(:parse, "twice")
)

row(
  "patterns.rest_comes_last",
  join_lines(["case [1, 2]", "when [*xs, x]", "  x", "end"]),
  fails(:parse, "comes last")
)

row(
  "patterns.rest_only_in_a_pattern",
  join_lines(["xs = [1]", "[0, *xs]"]),
  fails(:parse, "only in a pattern")
)

row(
  "patterns.formats",
  unlines(
    ["case v", "when [x,*rest]", "  rest", "when {name: name}", "  name", "end"]
  ),
  formats(
    unlines(
      ["case v", "when [x, *rest]", "  rest", "when {name:}", "  name", "end"]
    )
  )
)

row(
  "check.B0081.destructuring_covers",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "",
      "case rect(1, 2)",
      "when circle(r)",
      "  r",
      "when rect(w, h)",
      "  w * h",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0081.destructuring_misses",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "",
      "case rect(1, 2)",
      "when circle(r)",
      "  r",
      "end"
    ]
  ),
  diagnoses(["B0081"])
)

row(
  "check.B0081.refutable_arm_does_not_cover",
  join_lines(
    [
      "union shape = circle(r) | rect(w, h)",
      "",
      "case rect(1, 2)",
      "when circle(r)",
      "  r",
      "when rect(w, 1)",
      "  w",
      "end"
    ]
  ),
  diagnoses(["B0081"])
)
