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
  "e = error(:boom, \"why\")\n:still_running",
  value(":still_running")
)

row(
  "errors.throw",
  "# waive B0037: the row covers this spelling itself\nthrow(error(:parse, \"bad row\"))",
  fails(:eval, "parse: bad row"),
  covers("builtin:throw")
)

row(
  "errors.try",
  "# waive B0037: the row covers this spelling itself\ntry(throw(error(:boom, \"x\")), catch(e(), :handled))",
  value(":handled"),
  covers("builtin:try")
)

row("errors.try.no_throw", "try(1 + 1, catch(_e(), 0))", value("2"))

row(
  "errors.try.binding",
  "# waive B0037: the row covers this spelling itself\ntry(throw(error(:boom, \"x\")), catch(e(), error?(e)))",
  value("true")
)

row(
  "errors.readable.kind",
  "# waive B0036: the row covers this name itself\n# waive B0037: the row covers this spelling itself\ntry(throw(error(:boom, \"why\")), catch(e(), error_kind(e)))",
  value(":boom"),
  covers("builtin:error_kind"),
  pending("G4", "wasm")
)

row(
  "errors.readable.message",
  "# waive B0036: the row covers this name itself\n# waive B0037: the row covers this spelling itself\ntry(throw(error(:boom, \"why\")), catch(e(), error_message(e)))",
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
  "use(\"kyohi\", [:check, :enforce])\n[check(1, []), enforce(1, [], {})]",
  value("[[], nil]"),
  pending("G16", "wasm")
)

row(
  "errors.enforce.raises_the_findings",
  "use(\"kyohi\", [:check, :enforce, :refusal])\nrules = [(x) -> [refusal(:b, \"one\"), refusal(:a, \"two\")]]\ncaught = begin\n  enforce(0, rules, {kind: :first})\nrescue e\n  [e.kind, e.message]\nend\n[check(0, rules), caught]",
  value("[[[:b, \"one\"], [:a, \"two\"]], [:b, \"one; two\"]]"),
  covers("okite:D0014"),
  pending("G16", "wasm")
)
