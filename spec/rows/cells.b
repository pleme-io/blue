# Typed cells (docs/PURE-BLUE.md L1): the one place a value changes. A cell is
# read with cell_get and replaced with cell_put; a name is never rebound.

row(
  "cells.get_what_was_put_in",
  join_lines(["c = cell(1)", "cell_get(c)"]),
  value("1"),
  covers("builtin:cell", "builtin:cell_get")
)

row(
  "cells.put_replaces_and_answers_the_new_value",
  join_lines(["c = cell(1)", "r = cell_put(c, 2)", "[r, cell_get(c)]"]),
  value("[2, 2]"),
  covers("builtin:cell_put")
)

row(
  "cells.a_closure_shares_the_cell_it_holds",
  join_lines(
    [
      "c = cell(0)",
      "bump = () -> cell_put(c, cell_get(c) + 1)",
      "bump()",
      "bump()",
      "cell_get(c)"
    ]
  ),
  value("2")
)

row(
  "cells.a_cell_holds_any_value",
  join_lines(["c = cell([1, 2])", "cell_put(c, {a: 1})", "cell_get(c)"]),
  value("{a: 1}")
)

row(
  "cells.predicate",
  join_lines(["[cell?(cell(1)), cell?(1), cell?(nil)]"]),
  value("[true, false, false]"),
  covers("builtin:cell?")
)

row(
  "cells.reading_a_non_cell_raises_a_type_error",
  join_lines(
    ["caught = begin", "  cell_get(1)", "rescue e", "  e.kind", "end", "caught"]
  ),
  value(":type_error")
)
