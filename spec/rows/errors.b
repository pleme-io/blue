# Errors and refusals: error builds a value, throw raises it, try/catch
# handles it. A readable error and a catch that does not swallow program faults
# are the destination (G4).

row(
  "errors.error_is_a_value",
  "error?(error(:boom, \"why\"))",
  value("true"),
  covers("builtin:error", "builtin:error?")
)

row(
  "errors.error_does_not_raise",
  join_lines(["e = error(:boom, \"why\")", ":still_running"]),
  value(":still_running")
)

row(
  "errors.throw",
  join_lines(
    [
      "# waive B0037: the row covers this spelling itself",
      "throw(error(:parse, \"bad row\"))"
    ]
  ),
  fails(:eval, "parse: bad row"),
  covers("builtin:throw")
)

row(
  "errors.try",
  join_lines(
    [
      "# waive B0037: the row covers this spelling itself",
      "try(throw(error(:boom, \"x\")), catch(e(), :handled))"
    ]
  ),
  value(":handled"),
  covers("builtin:try")
)

row("errors.try.no_throw", "try(1 + 1, catch(_e(), 0))", value("2"))

row(
  "errors.raise.options_in_key_order",
  join_lines(
    [
      "def caught(i)",
      "  raise(:k, \"m\", {data: i * 0, cause: error(:inner, \"x\")})",
      "rescue e",
      "  e",
      "end",
      "length(distinct(map((i) -> string(caught(i)), range(0, 100))))"
    ]
  ),
  value("1")
)

row(
  "errors.try.binding",
  join_lines(
    [
      "# waive B0037: the row covers this spelling itself",
      "try(throw(error(:boom, \"x\")), catch(e(), error?(e)))"
    ]
  ),
  value("true")
)

row(
  "errors.readable.kind",
  join_lines(
    [
      "# waive B0036: the row covers this name itself",
      "# waive B0037: the row covers this spelling itself",
      "try(throw(error(:boom, \"why\")), catch(e(), error_kind(e)))"
    ]
  ),
  value(":boom"),
  covers("builtin:error_kind"),
  pending("G4", "wasm")
)

row(
  "errors.readable.message",
  join_lines(
    [
      "# waive B0036: the row covers this name itself",
      "# waive B0037: the row covers this spelling itself",
      "try(throw(error(:boom, \"why\")), catch(e(), error_message(e)))"
    ]
  ),
  value("\"why\""),
  covers("builtin:error_message"),
  pending("G4", "wasm")
)

row(
  "errors.to_s",
  "to_s(error(:boom, \"why\"))",
  value("\"error(:boom, \\\"why\\\")\""),
  pending("G4")
)

row(
  "errors.equal",
  "error(:boom, \"why\") == error(:boom, \"why\")",
  value("true"),
  pending("G4")
)

row(
  "errors.catch_does_not_swallow_bugs",
  "try(1 / 0, catch(_e(), :swallowed))",
  fails(:eval, "division by zero"),
  pending("G4")
)

row(
  "errors.value_render",
  "error(:boom, \"why\")",
  value("error(:boom, \"why\")"),
  pending("G4")
)

row("errors.uncaught_value", "x = raise(:boom, \"why\")", fails(:eval, "boom"))

row(
  "errors.enforce.sound",
  join_lines(
    ["use(\"kyohi\", [:check, :enforce])", "[check(1, []), enforce(1, [], {})]"]
  ),
  value("[[], nil]"),
  pending("G16", "wasm")
)

row(
  "errors.enforce.raises_the_findings",
  join_lines(
    [
      "use(\"kyohi\", [:check, :enforce, :refusal])",
      "rules = [(x) -> [refusal(:b, \"one\"), refusal(:a, \"two\")]]",
      "caught = begin",
      "  enforce(0, rules, {kind: :first})",
      "rescue e",
      "  [e.kind, e.message]",
      "end",
      "[check(0, rules), caught]"
    ]
  ),
  value("[[[:b, \"one\"], [:a, \"two\"]], [:b, \"one; two\"]]"),
  covers("okite:D0014"),
  pending("G16", "wasm")
)

row(
  "errors.kind.native_fn",
  join_lines(
    ["begin", "  first([])", "rescue :native_fn as e", "  e.kind", "end"]
  ),
  value(":native_fn")
)

row(
  "errors.kind.type_mismatch",
  join_lines(
    [
      "def at(m)",
      "  m[:k]",
      "end",
      "",
      "begin",
      "  at(nil)",
      "rescue :type_mismatch as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":type_mismatch")
)

row(
  "errors.kind.division_by_zero",
  join_lines(
    [
      "def div(a, b)",
      "  a / b",
      "end",
      "",
      "begin",
      "  div(1, 0)",
      "rescue :division_by_zero as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":division_by_zero")
)

row(
  "errors.kind.integer_overflow",
  join_lines(
    [
      "begin",
      "  9_223_372_036_854_775_807 + 1",
      "rescue :integer_overflow as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":integer_overflow")
)

row(
  "errors.kind.arity_mismatch",
  join_lines(
    [
      "fs = [fn(a) a end]",
      "begin",
      "  apply(fs[0], [1, 2])",
      "rescue :arity_mismatch as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":arity_mismatch")
)

row(
  "errors.kind.not_callable",
  join_lines(
    [
      "vs = [5]",
      "begin",
      "  apply(vs[0], [1])",
      "rescue :not_callable as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":not_callable")
)

row(
  "errors.kind.unbound_symbol",
  join_lines(
    [
      "begin",
      "  eval(read_forms(\"nope\")[0])",
      "rescue :unbound_symbol as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":unbound_symbol")
)

row(
  "errors.kind.depth_exceeded",
  join_lines(
    [
      "def deep(n)",
      "  1 + deep(n + 1)",
      "end",
      "",
      "begin",
      "  deep(0)",
      "rescue :depth_exceeded as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":depth_exceeded"),
  isolate()
)

row(
  "errors.kind.catch_all_reads_snake_case",
  join_lines(
    [
      "def div(a, b)",
      "  a / b",
      "end",
      "",
      "begin",
      "  div(1, 0)",
      "rescue e",
      "  [e.kind, to_s(e)]",
      "end"
    ]
  ),
  value("[:division_by_zero, \"division_by_zero: division by zero\"]")
)

row(
  "errors.kind.unmatched_is_raised_in_snake_case",
  join_lines(
    [
      "def div(a, b)",
      "  a / b",
      "end",
      "",
      "begin",
      "  div(1, 0)",
      "rescue :timeout",
      "  1",
      "end"
    ]
  ),
  fails(:eval, "division_by_zero: division by zero")
)

row(
  "errors.kind.caught_list_fault_names_no_lisp_word",
  join_lines(["begin", "  first([])", "rescue e", "  e.message", "end"]),
  value("\"the list is too short\"")
)

row(
  "errors.rescue.kebab_kind_is_read_in_snake_case",
  join_lines(
    [
      "def div(a, b)",
      "  a / b",
      "end",
      "",
      "begin",
      "  div(1, 0)",
      "rescue :division-by-zero as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":division_by_zero")
)
