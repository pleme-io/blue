# Refusals that flow: `x = f(y)?` binds the value of a result or an option
# and returns a refusal or a none from the function at once. A result is
# kyohi's declared union (`kyohi::ok` is `yes(v)`, `kyohi::refused` is
# `no(r)`) or the map `{ok: true, value: v}` / `{ok: false, refusal: r}`; an
# option is umu's `{some: true, value: v}` or `{some: false}`. `?` on any
# other value raises :usage. `?` ends a statement of a def body and lowers to
# a guard `return`. docs/GUARD-RETURN.md.

row(
  "refusals.flow",
  join_lines(
    [
      "def half(n)",
      "  if n % 2 == 0",
      "    {ok: true, value: n / 2}",
      "  else",
      "    {ok: false, refusal: [:odd, n]}",
      "  end",
      "end",
      "def quarter(n)",
      "  h = half(n)?",
      "  half(h)",
      "end",
      "[quarter(8), quarter(6), quarter(3)]"
    ]
  ),
  value("[{ok: true, value: 2}, {ok: false, refusal: [:odd, 3]}, {ok: false, refusal: [:odd, 3]}]"),
  covers("form:x = f(y)?")
)

row(
  "refusals.returns_at_once",
  join_lines(
    [
      "def no(why)",
      "  {ok: false, refusal: why}",
      "end",
      "def f()",
      "  _x = no(:stop)?",
      "  raise(:never, \"after a refusal\")",
      "end",
      "f"
    ]
  ),
  value("{ok: false, refusal: :stop}")
)

row(
  "refusals.a_statement_discards_the_value",
  join_lines(
    [
      "def check(n)",
      "  if n > 0",
      "    {ok: true, value: n}",
      "  else",
      "    {ok: false, refusal: :negative}",
      "  end",
      "end",
      "def f(n)",
      "  check(n)?",
      "  :fine",
      "end",
      "[f(1), f(-1)]"
    ]
  ),
  value("[:fine, {ok: false, refusal: :negative}]")
)

row(
  "refusals.last_call_is_the_value",
  join_lines(
    [
      "def id(r)",
      "  r",
      "end",
      "def f(r)",
      "  id(r)?",
      "end",
      "[f({ok: true, value: 7}), f({ok: false, refusal: 1})]"
    ]
  ),
  value("[7, {ok: false, refusal: 1}]")
)

row(
  "refusals.inside_a_branch",
  join_lines(
    [
      "def id(r)",
      "  r",
      "end",
      "def f(r, go)",
      "  if go",
      "    v = id(r)?",
      "    v + 1",
      "  else",
      "    0",
      "  end",
      "end",
      "[f({ok: true, value: 1}, true), f({ok: false, refusal: :x}, true), f(nil, false)]"
    ]
  ),
  value("[2, {ok: false, refusal: :x}, 0]")
)

row(
  "refusals.kyohi_results",
  join_lines(
    [
      "use(\"kyohi\", %i[ok refusal refused])",
      "def parse(s)",
      "  if s == \"\"",
      "    refused(refusal(:empty, \"nothing to read\"))",
      "  else",
      "    ok(s)",
      "  end",
      "end",
      "def both(a, b)",
      "  x = parse(a)?",
      "  y = parse(b)?",
      "  ok(concat(x, y))",
      "end",
      "[both(\"a\", \"b\"), both(\"a\", \"\")]"
    ]
  ),
  value("[kyohi::yes({value: \"ab\"}), kyohi::no({refusal: [:empty, \"nothing to read\"]})]"),
  pending("G16", "wasm")
)

row(
  "refusals.not_a_result",
  join_lines(
    [
      "def five(n)",
      "  n",
      "end",
      "def f()",
      "  x = five(5)?",
      "  x",
      "end",
      "f"
    ]
  ),
  fails(:eval, "`?` takes a result")
)

row(
  "refusals.inside_an_argument",
  join_lines(["def id(r)", "  r", "end", "def f(r)", "  [id(r)?]", "end"]),
  fails(:parse, "ends a statement")
)

row(
  "refusals.at_the_top_level",
  join_lines(["def id(r)", "  r", "end", "x = id({ok: true, value: 1})?"]),
  fails(:parse, "ends a statement")
)

row(
  "refusals.formats",
  unlines(["def f(r)", "  x = id(r)?", "  id(r)?", "  x", "end"]),
  formats(unlines(["def f(r)", "  x = id(r)?", "  id(r)?", "  x", "end"]))
)

row(
  "refusals.option_none_returns_at_once",
  join_lines(
    [
      "def half(n)",
      "  if n % 2 == 0",
      "    {some: true, value: n / 2}",
      "  else",
      "    {some: false}",
      "  end",
      "end",
      "def quarter(n)",
      "  h = half(n)?",
      "  half(h)",
      "end",
      "[quarter(8), quarter(6), quarter(3)]"
    ]
  ),
  value("[{some: true, value: 2}, {some: false}, {some: false}]")
)

row(
  "refusals.umu_options",
  join_lines(
    [
      "use(\"umu\", %i[none some value_or])",
      "def port(m)",
      "  if m[:port].nil?",
      "    none",
      "  else",
      "    some(m[:port])",
      "  end",
      "end",
      "def address(m)",
      "  p = port(m)?",
      "  some(concat(\"h:\", to_s(p)))",
      "end",
      "[value_or(address({port: 80}), \"-\"), value_or(address({}), \"-\")]"
    ]
  ),
  value("[\"h:80\", \"-\"]"),
  pending("G16", "wasm")
)

row(
  "refusals.result_union",
  join_lines(
    [
      "use(\"kyohi\", %i[ok refusal refused])",
      "def parse(s)",
      "  if s == \"\"",
      "    refused(refusal(:empty, \"nothing\"))",
      "  else",
      "    ok(s)",
      "  end",
      "end",
      "def both(a, b)",
      "  x = parse(a)?",
      "  y = parse(b)?",
      "  ok(concat(x, y))",
      "end",
      "def shown(r)",
      "  case r",
      "  when kyohi::yes(v)",
      "    v",
      "  when kyohi::no(why)",
      "    why[0]",
      "  end",
      "end",
      "[shown(both(\"a\", \"b\")), shown(both(\"a\", \"\")), kyohi::result?(both(\"\", \"\"))]"
    ]
  ),
  value("[\"ab\", :empty, true]"),
  pending("G16", "wasm")
)
