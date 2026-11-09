# The check stage: one row per rule in blue_lang_check::RULES (B0001-B0020),
# observed by `blue check` and in-process, plus the run door refusing an
# error-severity finding before anything runs, and the one escape hatch.

row(
  "check.B0001",
  join_lines(["def f(xs)", "  lenght(xs)", "end"]),
  diagnoses(["B0001"]),
  covers("rule:B0001")
)

row(
  "check.B0001.run_refuses",
  join_lines(["write_stdout(\"side effect\")", "nope()"]),
  fails(:check, "B0001"),
  covers("rule:B0001")
)

row(
  "check.B0002",
  join_lines(["def f(x)", "  y = x + 1", "  x", "end"]),
  diagnoses(["B0002"]),
  covers("rule:B0002")
)

row(
  "check.B0002.underscore",
  join_lines(["def f(x)", "  _y = x + 1", "  x", "end"]),
  diagnoses([])
)

row(
  "check.B0002.runs",
  join_lines(["def f(x)", "  y = x + 1", "  x", "end", "", "f(1)"]),
  value("1")
)

row(
  "check.B0003",
  join_lines(["def f(a: Int) -> Str", "  a + 1", "end"]),
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.B0004",
  join_lines(["def f(s: Str) -> Int", "  s + 1", "end"]),
  diagnoses(["B0004"]),
  covers("rule:B0004")
)

row(
  "check.B0005",
  join_lines(
    [
      "def add(a: Int, b: Int) -> Int",
      "  a + b",
      "end",
      "",
      "def g() -> Int",
      "  add(1, \"two\")",
      "end"
    ]
  ),
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row(
  "check.infer.literal",
  join_lines(["def f() -> Int", "  x = \"two\"", "  x", "end"]),
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.infer.parameter",
  join_lines(["def f(s: Str) -> Int", "  x = s", "  x + 1", "end"]),
  diagnoses(["B0004"]),
  covers("rule:B0004")
)

row(
  "check.infer.builtin_result",
  join_lines(["def f(s: Str) -> Int", "  n = upcase(s)", "  n", "end"]),
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.infer.if_join",
  join_lines(
    [
      "def f(a: Int) -> Int",
      "  x = if a > 0",
      "    \"p\"",
      "  else",
      "    \"n\"",
      "  end",
      "  x * 2",
      "end"
    ]
  ),
  diagnoses(["B0004"]),
  covers("rule:B0004")
)

row(
  "check.infer.if_join_unknown",
  join_lines(
    [
      "def f(a: Int, b) -> Int",
      "  x = if a > 0",
      "    \"p\"",
      "  else",
      "    b",
      "  end",
      "  x * 2",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.infer.builtin_argument",
  join_lines(["def shout(a: Int) -> Str", "  x = a + 1", "  upcase(x)", "end"]),
  diagnoses(["B0062"]),
  covers("rule:B0062")
)

row(
  "check.infer.branch_assignment",
  join_lines(
    [
      "def f(c: Bool) -> Int",
      "  x = \"s\"",
      "  if c",
      "    x = 1",
      "  end",
      "  x + 1",
      "end",
      "",
      "f(true)"
    ]
  ),
  value("2")
)

row(
  "check.infer.shadowed_builtin",
  join_lines(
    [
      "def length(_x)",
      "  \"long\"",
      "end",
      "",
      "def f(s: Str) -> Str",
      "  n = length(s)",
      "  n",
      "end",
      "",
      "f(\"a\")"
    ]
  ),
  value("\"long\"")
)

row(
  "check.infer.untyped",
  join_lines(["def f(_a)", "  x = \"s\"", "  x + 1", "end"]),
  diagnoses([])
)

row(
  "check.infer.list_literal",
  join_lines(["def f(a: Int) -> Int", "  [a]", "end"]),
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.infer.map_literal",
  join_lines(["def f(a: Int) -> Str", "  {b: a}", "end"]),
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.signature.map",
  join_lines(
    [
      "def total(m: Map(Sym, Int)) -> Int",
      "  m[:a]",
      "end",
      "",
      "def g(a: Int) -> Int",
      "  total({b: \"x\"}) + a",
      "end"
    ]
  ),
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row(
  "check.signature.map_runs",
  join_lines(
    [
      "def total(m: Map(Sym, Int)) -> Int",
      "  m[:a]",
      "end",
      "",
      "def g(a: Int) -> Int",
      "  total({a: 1, b: 2}) + a",
      "end",
      "",
      "g(1)"
    ]
  ),
  value("2")
)

row(
  "check.signature.record",
  join_lines(
    [
      "record point(x, y: Int)",
      "",
      "def height(p: point) -> Int",
      "  p.y",
      "end",
      "",
      "def g(a: Int) -> Int",
      "  height({x: a, y: a})",
      "end"
    ]
  ),
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row(
  "check.signature.record_field_type",
  join_lines(
    [
      "record point(x, y: Int)",
      "",
      "def label(p: point) -> Str",
      "  p.y",
      "end"
    ]
  ),
  diagnoses(["B0003"]),
  covers("rule:B0003")
)

row(
  "check.signature.record_unknown_field",
  join_lines(
    [
      "record point(x, y: Int)",
      "",
      "def depth(p: point) -> Int",
      "  p.z",
      "end"
    ]
  ),
  diagnoses(["B0079"]),
  covers("rule:B0079")
)

row(
  "check.signature.record_return",
  join_lines(
    [
      "record point(x, y: Int)",
      "",
      "def origin(a: Int) -> point",
      "  point(a, a)",
      "end",
      "",
      "def height(p: point) -> Int",
      "  p.y",
      "end",
      "",
      "def g(a: Int) -> Int",
      "  height(origin(a))",
      "end",
      "",
      "g(4)"
    ]
  ),
  value("4")
)

row(
  "check.signature.union",
  join_lines(
    [
      "union shape = circle(r: Int) | rect(w: Int, h: Int)",
      "record point(x, y)",
      "",
      "def area(s: shape) -> Int",
      "  case s",
      "  when circle?",
      "    3 * s.r * s.r",
      "  when rect?",
      "    s.w * s.h",
      "  end",
      "end",
      "",
      "def g(a: Int) -> Int",
      "  area(point(a, a))",
      "end"
    ]
  ),
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row(
  "check.signature.union_takes_an_arm",
  join_lines(
    [
      "union shape = circle(r: Int) | rect(w: Int, h: Int)",
      "",
      "def area(s: shape) -> Int",
      "  case s",
      "  when circle?",
      "    3 * s.r * s.r",
      "  when rect?",
      "    s.w * s.h",
      "  end",
      "end",
      "",
      "def g(a: Int) -> Int",
      "  area(circle(a)) + area(rect(a, 2))",
      "end",
      "",
      "g(2)"
    ]
  ),
  value("16")
)

row(
  "check.boundary.top_level",
  join_lines(["def inc(n: Int) -> Int", "  n + 1", "end", "", "inc(\"a\")"]),
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row(
  "check.boundary.top_level_refuses",
  join_lines(
    [
      "def inc(n: Int) -> Int",
      "  n + 1",
      "end",
      "",
      "write_stdout(\"side effect\")",
      "inc([1])"
    ]
  ),
  fails(:check, "B0005"),
  covers("rule:B0005")
)

row(
  "check.boundary.untyped_def",
  join_lines(
    [
      "def inc(n: Int) -> Int",
      "  n + 1",
      "end",
      "",
      "def loose(xs)",
      "  label = \"n\"",
      "  [inc(label), xs]",
      "end"
    ]
  ),
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row(
  "check.boundary.unknown_is_left",
  join_lines(
    [
      "def inc(n: Int) -> Int",
      "  n + 1",
      "end",
      "",
      "def loose(x)",
      "  inc(x)",
      "end",
      "",
      "loose(1)"
    ]
  ),
  value("2")
)

row(
  "check.boundary.opaque_type_is_left",
  join_lines(
    ["def shout(w: String) -> String", "  w", "end", "", "shout(\"a\")"]
  ),
  value("\"a\"")
)

row(
  "check.boundary.local_name",
  join_lines(
    [
      "def inc(n: Int) -> Int",
      "  n + 1",
      "end",
      "",
      "def loose(inc)",
      "  inc(\"a\")",
      "end",
      "",
      "loose((s) -> upcase(s))"
    ]
  ),
  value("\"A\"")
)

row(
  "check.boundary.qualified",
  join_lines(["use(\"sp_strict\")", "", "sp_strict::sp_scale(2, \"x\")"]),
  diagnoses(["B0005"]),
  covers("rule:B0005")
)

row(
  "check.boundary.qualified_runs",
  join_lines(["use(\"sp_strict\")", "", "sp_strict::sp_scale(2, 3)"]),
  value("6"),
  pending("G16", "wasm")
)

row(
  "check.B0082",
  join_lines(["blueshift(:strict)", "", "def twice(n)", "  n * 2", "end"]),
  diagnoses(["B0082"]),
  covers("rule:B0082")
)

row(
  "check.B0082.one_annotation_is_typed",
  join_lines(
    [
      "blueshift(:strict)",
      "",
      "def scale(n: Int, k)",
      "  n * k",
      "end",
      "",
      "def show(x) -> dyn",
      "  x",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0082.runs",
  join_lines(
    [
      "blueshift(:strict)",
      "",
      "def twice(n: Int) -> Int",
      "  n * 2",
      "end",
      "",
      "twice(21)"
    ]
  ),
  value("42")
)

row(
  "check.B0082.script_is_not_made_strict",
  join_lines(
    [
      "use(\"sp_strict\")",
      "",
      "def loose(x)",
      "  sp_strict::sp_scale(x, 2)",
      "end",
      "",
      "loose(3)"
    ]
  ),
  value("6"),
  pending("G16", "wasm")
)

row(
  "check.B0082.script_is_not_made_strict.clean",
  join_lines(
    [
      "use(\"sp_strict\")",
      "",
      "def loose(x)",
      "  sp_strict::sp_scale(x, 2)",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0082.waived",
  join_lines(
    [
      "blueshift(:strict)",
      "",
      "# waive B0082: the shape of a value it forwards is the caller's",
      "def pass(x)",
      "  x",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0006",
  unlines(["def f("]),
  diagnoses(["B0006"]),
  covers("rule:B0006")
)

row(
  "check.B0007",
  join_lines(["# waive B0001", "def f()", "  1", "end"]),
  diagnoses(["B0007"]),
  covers("rule:B0007")
)

row(
  "check.B0008",
  join_lines(
    ["# waive B0001: nothing here is unbound", "def f()", "  1", "end"]
  ),
  diagnoses(["B0008"]),
  covers("rule:B0008")
)

row(
  "check.B0009",
  join_lines(
    [
      "use(\"sp_amb_a\", [:sp_amb])",
      "use(\"sp_amb_b\", [:sp_amb])",
      "",
      "sp_amb()"
    ]
  ),
  diagnoses(["B0009"]),
  covers("rule:B0009")
)

row(
  "check.B0009.run_refuses",
  join_lines(
    [
      "use(\"sp_amb_a\", [:sp_amb])",
      "use(\"sp_amb_b\", [:sp_amb])",
      "",
      "sp_amb()"
    ]
  ),
  fails(:check, "B0009"),
  covers("rule:B0009"),
  pending("G16", "wasm")
)

row(
  "check.B0012",
  join_lines(["use(\"sp_mod\")", "sp_twice(1)"]),
  diagnoses(["B0012"]),
  covers("rule:B0012")
)

row(
  "check.B0013",
  join_lines(["use(\"sp_pre\")", "sp_pre::sp_pre_x"]),
  diagnoses(["B0013"]),
  covers("rule:B0013")
)

row(
  "check.B0014",
  join_lines(["use(\"sp_mg\")", "sp_mg::sp_a"]),
  diagnoses(["B0014"]),
  covers("rule:B0014")
)

row(
  "check.B0015",
  join_lines(
    [
      "use(\"sp_over\")",
      "use(\"sp_mod\")",
      "",
      "sp_mod::sp_twice(1)",
      "sp_over::first([1])"
    ]
  ),
  diagnoses(["B0015"]),
  covers("rule:B0015")
)

row(
  "check.B0016",
  join_lines(["use(\"sp_mod\")", "1"]),
  diagnoses(["B0016"]),
  covers("rule:B0016")
)

row(
  "check.B0017",
  join_lines(["def sp_f()", "  1", "end", "", "def sp_f()", "  2", "end"]),
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
  join_lines(["def f()", "  1", "end", "", "f()"]),
  diagnoses(["B0023"]),
  covers("rule:B0023")
)

row(
  "check.B0023.local_is_a_value",
  join_lines(
    ["def f()", "  1", "end", "", "def g(f)", "  f()", "end", "", "g(() -> 2)"]
  ),
  diagnoses([])
)

row(
  "check.B0023.argument_taking_function",
  join_lines(["def f(x)", "  x", "end", "", "f(1)"]),
  diagnoses([])
)

row(
  "check.B0019",
  join_lines(["use(\"sp_loose\")", "sp_loose::sp_l"]),
  diagnoses(["B0019"]),
  covers("rule:B0019")
)

row(
  "check.B0020",
  join_lines(["use(\"sp_mod\")", "sp_mod::sp_twice(1) + sp_mod / 2"]),
  diagnoses(["B0020"]),
  covers("rule:B0020")
)

row(
  "check.B0021",
  join_lines(["use(\"sp_lg\")", "sp_lg::lg_sp_hours"]),
  diagnoses(["B0021"]),
  covers("rule:B0021")
)

row(
  "check.B0022",
  join_lines(["use(\"sp_lg2\")", "sp_lg2::sp_hours"]),
  diagnoses(["B0022"]),
  covers("rule:B0022")
)

row(
  "check.waiver",
  join_lines(
    [
      "# waive B0001: the fixture needs a raise at runtime",
      "def f()",
      "  nope()",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.waiver.runs",
  join_lines(
    [
      "# waive B0001: the fixture needs a raise at runtime",
      "def f()",
      "  nope()",
      "end",
      "",
      "f"
    ]
  ),
  fails(:eval, "nope"),
  pending("G19", "vm")
)

row(
  "check.every_error_in_one_pass",
  join_lines(["def f()", "  a1()", "end", "", "def g()", "  a2()", "end"]),
  diagnoses(%w[B0001 B0001])
)

row(
  "check.unknown_type_name",
  join_lines(["def f(n: Itn) -> Int", "  1", "end"]),
  diagnoses(["B0010"]),
  pending("G8")
)

row(
  "check.test_blocks_checked",
  join_lines(["test \"t\"", "  assert nope() == 1", "end"]),
  diagnoses(["B0001"])
)

row(
  "check.B0010",
  join_lines(["def f(xs)", "  sp_mod::sp_twice(xs)", "end"]),
  diagnoses(["B0010"]),
  covers("rule:B0010")
)

row(
  "check.B0011",
  join_lines(["use(\"sp_mod\")", "", "sp_mod::sp_twicf(1)"]),
  diagnoses(["B0011"]),
  covers("rule:B0011")
)

row(
  "data.B0048",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"User\", fields: %i[id name]})",
      "",
      "def user_card(user: UserCard)",
      "  user.tone",
      "end"
    ]
  ),
  diagnoses(["B0048"]),
  covers("rule:B0048")
)

row(
  "data.B0048.child",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"User\", fields: %i[id name]})",
      "",
      "page = toriyose::danpen::fragment(",
      "  :page,",
      "  {on: \"Query\", fields: [{me: [\"...user_card\"]}]}",
      ")",
      "",
      "def page(data: Page)",
      "  data.me.name",
      "end"
    ]
  ),
  diagnoses(["B0048"])
)

row(
  "data.B0048.declared",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"User\", fields: %i[id name]})",
      "",
      "def user_card(user: UserCard)",
      "  [user.id, user[:name], user.__typename]",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "data.B0049",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"User\", fields: %i[id name]})",
      "",
      "page = toriyose::danpen::fragment(:page, {on: \"Query\", fields: [{me: [:id]}]})",
      "",
      "def user_card(user: UserCard)",
      "  user.name",
      "end",
      "",
      "def page(data: Page)",
      "  user_card(data.me)",
      "end"
    ]
  ),
  diagnoses(["B0049"]),
  covers("rule:B0049")
)

row(
  "data.B0049.unknown",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "page = toriyose::danpen::fragment(",
      "  :page,",
      "  {on: \"Query\", fields: [{me: [\"...nobody\"]}]}",
      ")"
    ]
  ),
  diagnoses(["B0049"])
)

row(
  "data.B0049.composed",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"User\", fields: %i[id name]})",
      "",
      "page = toriyose::danpen::fragment(",
      "  :page,",
      "  {on: \"Query\", fields: [{me: [\"...user_card\"]}]}",
      ")",
      "",
      "def user_card(user: UserCard)",
      "  user.name",
      "end",
      "",
      "def page(data: Page)",
      "  user_card(data.me)",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "data.B0050",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"User\", fields: %i[id nmae]})"
    ]
  ),
  diagnoses(["B0050"]),
  covers("rule:B0050"),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0050.type",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"Person\", fields: [:id]})"
    ]
  ),
  diagnoses(["B0050"]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0050.labels",
  join_lines(
    [
      "use(\"gamen\", [:labels])",
      "",
      "TONES = labels(:Tone, {WARM: \"Warm\", HOT: \"Hot\"})"
    ]
  ),
  diagnoses(["B0050"]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0050.holds",
  join_lines(
    [
      "use(\"toriyose/danpen\")",
      "",
      "card = toriyose::danpen::fragment(:user_card, {on: \"User\", fields: %i[id name]})"
    ]
  ),
  diagnoses([]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0051",
  "TONES = %i[WARM COOL]",
  diagnoses(["B0051"]),
  covers("rule:B0051"),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "data.B0051.labels",
  join_lines(
    [
      "use(\"gamen\", [:labels])",
      "",
      "TONES = labels(:Tone, {WARM: \"Warm\", COOL: \"Cool\"})"
    ]
  ),
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
  join_lines(
    ["test \"text\"", "  assert \"query Me { me { id } }\" != \"\"", "end"]
  ),
  diagnoses([]),
  frontend("{types: {\"User\" => {\"id\" => \"ID\", \"name\" => \"String\"}}, enums: {\"Tone\" => [\"WARM\", \"COOL\"]}}")
)

row(
  "safety.B0053",
  join_lines(["def put(m)", "  assoc(m, :a, 1)", "  m", "end"]),
  diagnoses(["B0053"]),
  covers("rule:B0053")
)

row(
  "safety.B0053.bound_or_last",
  join_lines(
    ["def put(m)", "  n = assoc(m, :a, 1)", "  assoc(n, :b, 2)", "end"]
  ),
  diagnoses([])
)

row(
  "safety.B0053.waived",
  join_lines(
    [
      "# waive B0053: the join raises on a list that is not text",
      "def put(xs)",
      "  join(xs, \",\")",
      "  xs",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "safety.B0061",
  join_lines(
    [
      "def prepared(opts)",
      "  opts[:vars]",
      "end",
      "",
      "prepared({variables: 1})"
    ]
  ),
  diagnoses(["B0061"]),
  covers("rule:B0061")
)

row(
  "safety.B0061.checked",
  join_lines(
    [
      "def checked(o, _ks)",
      "  o",
      "end",
      "",
      "def prepared(opts)",
      "  opts = checked(opts, [:vars])",
      "  [opts[:vars], opts.b]",
      "end"
    ]
  ),
  diagnoses(["B0061"])
)

row(
  "safety.B0061.read_key",
  join_lines(
    ["def prepared(opts)", "  opts[:vars]", "end", "", "prepared({vars: 1})"]
  ),
  diagnoses([])
)

row(
  "safety.B0062",
  join_lines(
    [
      "def kind_of(schema)",
      "  schema[:kind]",
      "end",
      "",
      "kind_of(\"type Query { a: Int }\")"
    ]
  ),
  diagnoses(["B0062"]),
  covers("rule:B0062")
)

row(
  "safety.B0062.kind_tested",
  join_lines(
    [
      "def kind_of(schema)",
      "  if map?(schema)",
      "    schema[:kind]",
      "  end",
      "end",
      "",
      "kind_of(\"type Query { a: Int }\")"
    ]
  ),
  diagnoses([])
)

row(
  "safety.B0062.collection_first_is_fixed",
  join_lines(
    [
      "def pairs(ys)",
      "  flat_map((x) -> [x, x], ys)",
      "end",
      "",
      "find((x) -> x > 1, [1, 2, 3])",
      "group_by((x) -> x % 2, pairs([1]))"
    ]
  ),
  fixes(
    join_lines(
      [
        "def pairs(ys)",
        "  flat_map(ys, (x) -> [x, x])",
        "end",
        "",
        "find([1, 2, 3], (x) -> x > 1)",
        "group_by(pairs([1]), (x) -> x % 2)"
      ]
    )
  )
)

row(
  "safety.B0062.a_function_second_is_left",
  join_lines(
    [
      "def inc(x)",
      "  x + 1",
      "end",
      "",
      "find((x) -> x, inc)",
      "find(5, (x) -> x)"
    ]
  ),
  fixes(
    join_lines(
      [
        "def inc(x)",
        "  x + 1",
        "end",
        "",
        "find((x) -> x, inc)",
        "find(5, (x) -> x)"
      ]
    )
  )
)

row(
  "safety.B0063",
  join_lines(
    [
      "def pin()",
      "  1",
      "end",
      "",
      "def gate(f)",
      "  f()",
      "end",
      "",
      "gate(pin)"
    ]
  ),
  diagnoses(["B0063"]),
  covers("rule:B0063")
)

row(
  "safety.B0063.lambda",
  join_lines(
    [
      "def pin()",
      "  1",
      "end",
      "",
      "def gate(f)",
      "  f()",
      "end",
      "",
      "gate(() -> pin)"
    ]
  ),
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

row(
  "check.B0070",
  join_lines(["def tally(ns)", "  reduce((acc, n) -> acc + n, 0, ns)", "end"]),
  diagnoses(["B0070"]),
  covers("rule:B0070")
)

row(
  "check.B0070.waived",
  join_lines(
    [
      "# waive B0070: tally will round, and the word never will",
      "def tally(ns)",
      "  reduce((acc, n) -> acc + n, 0, ns)",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0070.stale_waiver",
  join_lines(["# waive B0070: nothing to waive", "def own(z)", "  z", "end"]),
  diagnoses(["B0008"])
)

row(
  "check.B0072",
  join_lines(["def pair(a, b)", "  [a, b]", "end", "", "pair(1)"]),
  diagnoses(["B0072"]),
  covers("rule:B0072")
)

row(
  "check.B0072.optional_and_rest_take_a_range",
  join_lines(["def one(a, b?)", "  [a, b]", "end", "", "one(1)", "one(1, 2)"]),
  diagnoses([])
)

row(
  "check.B0072.waived",
  join_lines(
    [
      "def pair(a, b)",
      "  [a, b]",
      "end",
      "",
      "# waive B0072: shown by a person",
      "def f()",
      "  pair(1)",
      "end"
    ]
  ),
  diagnoses([])
)

row(
  "check.B0071",
  join_lines(["def apply()", "  1", "end"]),
  diagnoses(["B0071"]),
  covers("rule:B0071")
)

row(
  "check.B0073",
  join_lines(["path = \"retsu\"", "use(path)"]),
  diagnoses(["B0073"]),
  covers("rule:B0073")
)

row(
  "check.B0074",
  join_lines(["use(\"sp_moved\", [:sp_one])", "sp_one"]),
  diagnoses(["B0074"]),
  covers("rule:B0074")
)

row(
  "check.B0074.qualifier",
  join_lines(["use(\"sp_moved\")", "sp_moved::sp_one"]),
  diagnoses(%w[B0074 B0074])
)

row(
  "check.B0076",
  join_lines(["use(\"sp_tree\")", "sp_moved::sp_one"]),
  diagnoses(["B0076"]),
  covers("rule:B0076")
)

row(
  "check.B0076.full_path_is_clean",
  join_lines(["use(\"sp_tree\")", "sp_tree::sp_moved::sp_one"]),
  diagnoses([])
)

row(
  "check.B0077",
  join_lines(["use(%i[sp_tree sp_moved])", "sp_tree::sp_moved::sp_one"]),
  diagnoses(["B0077"]),
  covers("rule:B0077")
)

row(
  "check.B0078",
  join_lines(
    [
      "use(\"sp_tree\")",
      "use(\"sp_tree/sp_moved\")",
      "sp_tree::sp_moved::sp_one"
    ]
  ),
  diagnoses(["B0078"]),
  covers("rule:B0078")
)

row(
  "check.B0071.stops_the_run",
  join_lines(["def apply()", "  1", "end", "", "x = apply", "to_s(x)"]),
  fails(:check, "B0071")
)

row(
  "check.B0071.a_builtin_name_alone_is_no_fault",
  join_lines(["def size(_xs)", "  99", "end"]),
  diagnoses([])
)

row(
  "check.B0071.waived",
  join_lines(
    ["# waive B0071: reached qualified", "def apply(a)", "  a", "end"]
  ),
  diagnoses([])
)
