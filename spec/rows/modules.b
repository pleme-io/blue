# Modules: `use` against today's semantics, with the fixture packages in
# spec/bidamas/. The WASM surface has no loader, so it misses every `use` until
# G16 gives it one. Rows for the namespace design (theory/BLUE-NAMESPACES.md)
# state that destination and are pending on `namespaces`.

row(
  "modules.use",
  join_lines(["use(\"sp_mod\", [:sp_twice])", "sp_twice(4)"]),
  value("8"),
  covers("form:use(\"retsu\")"),
  pending("G16", "wasm")
)

row(
  "modules.use.real_bidama",
  join_lines(
    [
      "use(\"retsu\", [:is_empty, :size])",
      "[size(nil), size([1, 2]), is_empty(nil), is_empty([])]"
    ]
  ),
  value("[0, 2, true, true]"),
  pending("G16", "wasm")
)

row(
  "modules.kyohi.enforce",
  join_lines(
    [
      "use(\"kyohi\", [:check, :enforce, :refusal])",
      "rule = (x) -> [refusal(:bad, \"x is bad\")]",
      "[length(check(1, [rule])), enforce(1, [rule], {kind: :first}) rescue 0]"
    ]
  ),
  value("[1, 0]"),
  covers("okite:D0014"),
  pending("G16", "wasm")
)

row(
  "modules.use.missing",
  join_lines(["use(\"sp_no_such_package\")", "1"]),
  fails(:import, "no bidama named \"sp_no_such_package\"")
)

row(
  "modules.use.twice_is_once",
  join_lines(
    [
      "use(\"sp_mod\", [:sp_twice])",
      "# waive B0015: the row loads it twice on purpose",
      "use(\"sp_mod\")",
      "sp_twice(1)"
    ]
  ),
  value("2"),
  pending("G16", "wasm")
)

row("modules.use.unbound_without", "sp_twice(4)", fails(:check, "B0001"))

row(
  "modules.manifest.frontend_is_a_bluefile_word",
  "frontend(\"console\", {views: [\"views\"]})",
  fails(:check, "B0001")
)

row(
  "modules.use.transitive",
  join_lines(["use(\"sp_uses\", [:sp_quad])", "sp_quad(1)"]),
  value("4"),
  pending("G16", "wasm")
)

row(
  "modules.ns.qualified",
  join_lines(["use(\"sp_mod\")", "sp_mod::sp_twice(2)"]),
  value("4"),
  pending("G16", "wasm")
)

row(
  "modules.ns.builtin_qualified",
  join_lines(["use(\"sp_over\", [:first])", "blue::first([1, 2])"]),
  value("1"),
  pending("G16", "wasm")
)

row(
  "modules.ns.import_list",
  join_lines(["use(\"sp_mod\", [:sp_twice])", "sp_twice(3)"]),
  value("6"),
  pending("G16", "wasm")
)

row(
  "modules.ns.own_beats_importer",
  join_lines(
    [
      "use(\"sp_own\", [:sp_call_helper])",
      "",
      "def sp_helper()",
      "  :entry",
      "end",
      "",
      "sp_call_helper"
    ]
  ),
  value(":bidama"),
  pending("G16", "wasm")
)

row(
  "modules.ns.builtin_not_replaced",
  join_lines(["use(\"sp_over\")", "first([1, 2])"]),
  value("1"),
  pending("G16", "wasm")
)

row(
  "modules.ns.transitive_invisible",
  join_lines(["use(\"sp_uses\")", "sp_twice(1)"]),
  fails(:check, "B0012")
)
