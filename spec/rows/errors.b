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
  "throw(error(:parse, \"bad row\"))",
  fails(:eval, "uncaught"),
  covers("form:throw(error(:parse, \"bad row\"))"),
  covers("builtin:throw")
)

row(
  "errors.try",
  "try(throw(error(:boom, \"x\")), catch(e(), :handled))",
  value(":handled"),
  covers("form:try(risky(), catch(e(), fallback(e)))"),
  covers("builtin:try")
)

row("errors.try.no_throw", "try(1 + 1, catch(_e(), 0))", value("2"))

row(
  "errors.try.binding",
  "try(throw(error(:boom, \"x\")), catch(e(), error?(e)))",
  value("true")
)

row(
  "errors.readable.kind",
  "try(throw(error(:boom, \"why\")), catch(e(), error_kind(e)))",
  value(":boom"),
  pending("G4")
)

row(
  "errors.readable.message",
  "try(throw(error(:boom, \"why\")), catch(e(), error_message(e)))",
  value("\"why\""),
  pending("G4")
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

row(
  "errors.uncaught_value",
  "x = throw(error(:boom, \"why\"))",
  fails(:eval, "boom")
)
