# Modules: `use` against today's semantics, with the fixture packages in
# spec/bidamas/. The WASM surface has no loader, so it misses every `use` until
# G16 gives it one. Rows for the namespace design (theory/BLUE-NAMESPACES.md)
# state that destination and are pending on `namespaces`.

row(
  "modules.use",
  "use(\"sp_mod\", [:sp_twice])\nsp_twice(4)",
  value("8"),
  covers("form:use(\"retsu\")"),
  pending("G16", "wasm")
)

row(
  "modules.use.real_bidama",
  "use(\"retsu\", [:is_empty, :size])\n[size(nil), size([1, 2]), is_empty(nil), is_empty([])]",
  value("[0, 2, true, true]"),
  pending("G16", "wasm")
)

row(
  "modules.use.missing",
  "use(\"sp_no_such_package\")\n1",
  fails(:import, "no bidama named \"sp_no_such_package\"")
)

row(
  "modules.use.twice_is_once",
  "use(\"sp_mod\", [:sp_twice])\n# waive B0015: the row loads it twice on purpose\nuse(\"sp_mod\")\nsp_twice(1)",
  value("2"),
  pending("G16", "wasm")
)

row("modules.use.unbound_without", "sp_twice(4)", fails(:check, "B0001"))

row(
  "modules.use.transitive",
  "use(\"sp_uses\", [:sp_quad])\nsp_quad(1)",
  value("4"),
  pending("G16", "wasm")
)

row(
  "modules.ns.qualified",
  "use(\"sp_mod\")\nsp_mod::sp_twice(2)",
  value("4"),
  pending("G16", "wasm")
)

row(
  "modules.ns.builtin_qualified",
  "use(\"sp_over\", [:first])\nblue::first([1, 2])",
  value("1"),
  pending("namespaces")
)

row(
  "modules.ns.import_list",
  "use(\"sp_mod\", [:sp_twice])\nsp_twice(3)",
  value("6"),
  pending("G16", "wasm")
)

row(
  "modules.ns.own_beats_importer",
  "use(\"sp_own\")\n\ndef sp_helper()\n  :entry\nend\n\nsp_call_helper()",
  value(":bidama"),
  pending("namespaces")
)

row(
  "modules.ns.builtin_not_replaced",
  "use(\"sp_over\")\nfirst([1, 2])",
  value("1"),
  pending("namespaces")
)

row(
  "modules.ns.transitive_invisible",
  "use(\"sp_uses\")\nsp_twice(1)",
  fails(:check, "B0012")
)
