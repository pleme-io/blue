# The check stage: one row per rule in blue_lang_check::RULES (B0001-B0020),
# observed by `blue check` and in-process, plus the run door refusing an
# error-severity finding before anything runs, and the one escape hatch.

row(
  "check.B0001",
  "def f(xs)\n  lenght(xs)\nend",
  diagnoses(["B0001"]),
  covers("rule:B0001")
)

row(
  "check.B0001.run_refuses",
  "write_stdout(\"side effect\")\nnope()",
  fails(:check, "B0001"),
  covers("rule:B0001")
)

row(
  "check.B0002",
  "def f(x)\n  y = x + 1\n  x\nend",
  diagnoses(["B0002"]),
  covers("rule:B0002")
)

row("check.B0002.underscore", "def f(x)\n  _y = x + 1\n  x\nend", diagnoses([]))
row("check.B0002.runs", "def f(x)\n  y = x + 1\n  x\nend\n\nf(1)", value("1"))

row(
  "check.B0003",
  "def f(a: Int) -> Str\n  a + 1\nend",
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.B0004",
  "def f(s: Str) -> Int\n  s + 1\nend",
  diagnoses(["B0004"]),
  covers("rule:B0004")
)

row(
  "check.B0005",
  "def add(a: Int, b: Int) -> Int\n  a + b\nend\n\ndef g() -> Int\n  add(1, \"two\")\nend",
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row("check.B0006", "def f(\n", diagnoses(["B0006"]), covers("rule:B0006"))

row(
  "check.B0007",
  "# waive B0001\ndef f()\n  1\nend",
  diagnoses(["B0007"]),
  covers("rule:B0007")
)

row(
  "check.B0008",
  "# waive B0001: nothing here is unbound\ndef f()\n  1\nend",
  diagnoses(["B0008"]),
  covers("rule:B0008")
)

row(
  "check.B0009",
  "use(\"sp_amb_a\", [:sp_amb])\nuse(\"sp_amb_b\", [:sp_amb])\n\nsp_amb()",
  diagnoses(["B0009"]),
  covers("rule:B0009")
)

row(
  "check.B0009.run_refuses",
  "use(\"sp_amb_a\", [:sp_amb])\nuse(\"sp_amb_b\", [:sp_amb])\n\nsp_amb()",
  fails(:check, "B0009"),
  covers("rule:B0009"),
  pending("G16", "wasm")
)

row(
  "check.B0012",
  "use(\"sp_mod\")\nsp_twice(1)",
  diagnoses(["B0012"]),
  covers("rule:B0012")
)

row(
  "check.B0013",
  "use(\"sp_pre\")\nsp_pre::sp_pre_x",
  diagnoses(["B0013"]),
  covers("rule:B0013")
)

row(
  "check.B0014",
  "use(\"sp_mg\")\nsp_mg::sp_a",
  diagnoses(["B0014"]),
  covers("rule:B0014")
)

row(
  "check.B0015",
  "use(\"sp_over\")\nuse(\"sp_mod\")\n\nsp_mod::sp_twice(1)\nsp_over::first([1])",
  diagnoses(["B0015"]),
  covers("rule:B0015")
)

row(
  "check.B0016",
  "use(\"sp_mod\")\n1",
  diagnoses(["B0016"]),
  covers("rule:B0016")
)

row(
  "check.B0017",
  "def sp_f()\n  1\nend\n\ndef sp_f()\n  2\nend",
  diagnoses(["B0017"]),
  covers("rule:B0017")
)

row(
  "check.B0018",
  "blue::length([1])",
  diagnoses(["B0018"]),
  covers("rule:B0018")
)

row(
  "check.B0023",
  "def f()\n  1\nend\n\nf()",
  diagnoses(["B0023"]),
  covers("rule:B0023")
)

row(
  "check.B0023.local_is_a_value",
  "def f()\n  1\nend\n\ndef g(f)\n  f()\nend\n\ng(() -> 2)",
  diagnoses([])
)

row(
  "check.B0023.argument_taking_function",
  "def f(x)\n  x\nend\n\nf(1)",
  diagnoses([])
)

row(
  "check.B0019",
  "use(\"sp_loose\")\nsp_loose::sp_l",
  diagnoses(["B0019"]),
  covers("rule:B0019")
)

row(
  "check.B0020",
  "use(\"sp_mod\")\nsp_mod::sp_twice(1) + sp_mod / 2",
  diagnoses(["B0020"]),
  covers("rule:B0020")
)

row(
  "check.B0021",
  "use(\"sp_lg\")\nsp_lg::lg_sp_hours",
  diagnoses(["B0021"]),
  covers("rule:B0021")
)

row(
  "check.B0022",
  "use(\"sp_lg2\")\nsp_lg2::sp_hours",
  diagnoses(["B0022"]),
  covers("rule:B0022")
)

row(
  "check.waiver",
  "# waive B0001: the fixture needs a raise at runtime\ndef f()\n  nope()\nend",
  diagnoses([])
)

row(
  "check.waiver.runs",
  "# waive B0001: the fixture needs a raise at runtime\ndef f()\n  nope()\nend\n\nf",
  fails(:eval, "nope"),
  pending("G19", "vm")
)

row(
  "check.every_error_in_one_pass",
  "def f()\n  a1()\nend\n\ndef g()\n  a2()\nend",
  diagnoses(["B0001", "B0001"])
)

row(
  "check.unknown_type_name",
  "def f(n: Itn) -> Int\n  1\nend",
  diagnoses(["B0010"]),
  pending("G8")
)

row(
  "check.test_blocks_checked",
  "test \"t\"\n  assert nope() == 1\nend",
  diagnoses(["B0001"])
)

row(
  "check.B0010",
  "def f(xs)\n  sp_mod::sp_twice(xs)\nend",
  diagnoses(["B0010"]),
  covers("rule:B0010")
)

row(
  "check.B0011",
  "use(\"sp_mod\")\n\nsp_mod::sp_twicf(1)",
  diagnoses(["B0011"]),
  covers("rule:B0011")
)

row(
  "data.B0048",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :name]})\n\ndef user_card(user: UserCard)\n  user.tone\nend",
  diagnoses(["B0048"]),
  covers("rule:B0048")
)

row(
  "data.B0048.child",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :name]})\n\npage = danpen::fragment(:page, {on: \"Query\", fields: [{me: [\"...user_card\"]}]})\n\ndef page(data: Page)\n  data.me.name\nend",
  diagnoses(["B0048"])
)

row(
  "data.B0048.declared",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :name]})\n\ndef user_card(user: UserCard)\n  [user.id, get(user, :name), user.__typename]\nend",
  diagnoses([])
)

row(
  "data.B0049",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :name]})\n\npage = danpen::fragment(:page, {on: \"Query\", fields: [{me: [:id]}]})\n\ndef user_card(user: UserCard)\n  user.name\nend\n\ndef page(data: Page)\n  user_card(data.me)\nend",
  diagnoses(["B0049"]),
  covers("rule:B0049")
)

row(
  "data.B0049.unknown",
  "use(\"danpen\")\n\npage = danpen::fragment(:page, {on: \"Query\", fields: [{me: [\"...nobody\"]}]})",
  diagnoses(["B0049"])
)

row(
  "data.B0049.composed",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :name]})\n\npage = danpen::fragment(:page, {on: \"Query\", fields: [{me: [\"...user_card\"]}]})\n\ndef user_card(user: UserCard)\n  user.name\nend\n\ndef page(data: Page)\n  user_card(data.me)\nend",
  diagnoses([])
)

row(
  "data.B0050",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :nmae]})",
  diagnoses(["B0050"]),
  covers("rule:B0050"),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0050.type",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"Person\", fields: [:id]})",
  diagnoses(["B0050"]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0050.labels",
  "use(\"gamen\", [:labels])\n\nTONES = labels(:Tone, {WARM: \"Warm\", HOT: \"Hot\"})",
  diagnoses(["B0050"]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0050.holds",
  "use(\"danpen\")\n\ncard = danpen::fragment(:user_card, {on: \"User\", fields: [:id, :name]})",
  diagnoses([]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0051",
  "TONES = [:WARM, :COOL]",
  diagnoses(["B0051"]),
  covers("rule:B0051"),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0051.labels",
  "use(\"gamen\", [:labels])\n\nTONES = labels(:Tone, {WARM: \"Warm\", COOL: \"Cool\"})",
  diagnoses([]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0052",
  "me = \"query Me { me { id } }\"",
  diagnoses(["B0052"]),
  covers("rule:B0052"),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0052.test",
  "test \"text\"\n  assert \"query Me { me { id } }\" != \"\"\nend",
  diagnoses([]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "safety.B0053",
  "def put(m)\n  assoc(m, :a, 1)\n  m\nend",
  diagnoses(["B0053"]),
  covers("rule:B0053")
)

row(
  "safety.B0053.bound_or_last",
  "def put(m)\n  n = assoc(m, :a, 1)\n  assoc(n, :b, 2)\nend",
  diagnoses([])
)

row(
  "safety.B0053.waived",
  "# waive B0053: the join raises on a list that is not text\ndef put(xs)\n  join(xs, \",\")\n  xs\nend",
  diagnoses([])
)

row(
  "safety.B0061",
  "def prepared(opts)\n  get(opts, :vars)\nend\n\nprepared({variables: 1})",
  diagnoses(["B0061"]),
  covers("rule:B0061")
)

row(
  "safety.B0061.checked",
  "def checked(o, _ks)\n  o\nend\n\ndef prepared(opts)\n  opts = checked(opts, [:vars])\n  [get(opts, :vars), opts.b]\nend",
  diagnoses(["B0061"])
)

row(
  "safety.B0061.read_key",
  "def prepared(opts)\n  get(opts, :vars)\nend\n\nprepared({vars: 1})",
  diagnoses([])
)

row(
  "safety.B0062",
  "def kind_of(schema)\n  get(schema, :kind)\nend\n\nkind_of(\"type Query { a: Int }\")",
  diagnoses(["B0062"]),
  covers("rule:B0062")
)

row(
  "safety.B0062.kind_tested",
  "def kind_of(schema)\n  if map?(schema)\n    get(schema, :kind)\n  end\nend\n\nkind_of(\"type Query { a: Int }\")",
  diagnoses([])
)

row(
  "safety.B0062.collection_first_is_fixed",
  "def pairs(ys)\n  flat_map((x) -> [x, x], ys)\nend\n\nfind((x) -> x > 1, [1, 2, 3])\ngroup_by((x) -> x % 2, pairs([1]))",
  fixes("def pairs(ys)\n  flat_map(ys, (x) -> [x, x])\nend\n\nfind([1, 2, 3], (x) -> x > 1)\ngroup_by(pairs([1]), (x) -> x % 2)")
)

row(
  "safety.B0062.a_function_second_is_left",
  "def inc(x)\n  x + 1\nend\n\nfind((x) -> x, inc)\nfind(5, (x) -> x)",
  fixes("def inc(x)\n  x + 1\nend\n\nfind((x) -> x, inc)\nfind(5, (x) -> x)")
)

row(
  "safety.B0063",
  "def pin()\n  1\nend\n\ndef gate(f)\n  f()\nend\n\ngate(pin)",
  diagnoses(["B0063"]),
  covers("rule:B0063")
)

row(
  "safety.B0063.lambda",
  "def pin()\n  1\nend\n\ndef gate(f)\n  f()\nend\n\ngate(() -> pin)",
  diagnoses([])
)

row(
  "safety.B0064",
  "write_file(\"gate.b\", \"x=1\")",
  diagnoses(["B0064"]),
  covers("rule:B0064")
)

row(
  "safety.B0064.write_program",
  "write_program(\"gate.b\", \"x=1\")",
  diagnoses([])
)
