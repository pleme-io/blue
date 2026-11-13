@moduledoc """
tesuto (テスト) — testing: errors and snapshots as assertions, and the policy that holds every definition to a test beside it.

    uncovered({"uncovered" => []}) #=> []
"""

use("hadome")
use("moji", %i[before_first checked trim])
use("retsu", %i[first last rest size])

@doc """
raises?: whether f raises that kind of error.
"""
def raises?(kind, f)
  f()
  false
rescue e
  e.kind == kind
end

def literal(value)
  if string?(value)
    json_stringify(value)
  else
    to_s(value)
  end
end

@doc """
skip_for: end this test as skipped when `why` names a reason, and go on when it is nil. `blue test` counts it apart from a pass and prints the reason; `BLUE_TEST_SKIP=refuse` makes it a failure.

    skip_for(nil) #=> nil
    (skip_for("no kernel here") rescue :skipped) #=> :skipped
"""
def skip_for(why)
  if why != nil
    raise(:test_skipped, why)
  end
end

def snapshot_path(opts)
  name = opts[:name]
  if not string?(name) or name == "" or contains?(name, "/")
    raise(:bad_option, "a snapshot takes name: text with no slash")
  end
  path_join(opts[:dir] or "snapshots", "#{name}.b")
end

@doc """
snapshot: compare a value with its stored copy; update on request.
"""
def snapshot(value, opts)
  checked(opts, %i[name dir update])
  path = snapshot_path(opts)
  actual = unlines([literal(value)])
  if opts[:update] == true
    mkdir_p(path_dirname(path))
    write_file(path, actual)
    nil
  elsif not path_exists(path)
    raise(
      :snapshot_missing,
      "no snapshot at #{path}; run with update: true to record it",
      {data: {path:, actual:}}
    )
  else
    expected = read_file(path)
    if expected != actual
      raise(
        :snapshot_mismatch,
        join_lines(
          [
            "snapshot #{path} differs",
            "expected: #{expected}actual:   #{actual}"
          ]
        ),
        {data: {path:, expected:, actual:}}
      )
    end
    nil
  end
end

def scratch()
  path_join(temp_dir("tesuto"), "scratch")
end

@doc """
fresh_dir: A new, empty directory under TMPDIR whose name starts with `label`, made now: one per test that needs a directory. The run owns it (`temp_dir`), so it is gone when the run ends, however the run ends.

    starts_with?(path_basename(fresh_dir("doc")), "doc-") #=> true
"""
def fresh_dir(label)
  temp_dir(label)
end

def caught(f)
  f()
  nil
rescue e
  e
end

@doc """
uncovered: The definitions no test reached, from one record of
`blue test --coverage --json`. A record with no uncovered list is refused:
absent coverage is not full coverage.

    uncovered({"uncovered" => []}) #=> []
"""
def uncovered(coverage)
  names = if map?(coverage)
    coverage["uncovered"]
  end
  if not list?(names)
    raise(:coverage, "a coverage record carries no uncovered list")
  end
  names
end

@doc """
levels: The three levels a package can be held at, from weakest to strongest.

    levels #=> [:off, :audit, :enforce]
"""
def levels()
  %i[off audit enforce]
end

@doc """
level: A policy entry: definitions in `scope` (a package name, or "*" for every
package) are held at `value`, one of `levels`.

    get(level("*", :audit, "new gate"), :level) #=> :audit
"""
def level(scope, value, why)
  {entry: :level, scope:, level: value, why:}
end

@doc """
waive: A policy entry: the qualified definition `name` may go untested until the
date `until` (YYYY-MM-DD), for the reason `why`.

    get(waive("kazu::clamp", "in review", "2026-12-01"), :until) #=> "2026-12-01"
"""
def waive(name, why, until)
  {entry: :waive, name:, why:, until:}
end

@doc """
iso_date?: True for a YYYY-MM-DD shaped string; anything else is false.

    iso_date?("2026-10-24") #=> true
    iso_date?(20261024) #=> false
"""
def iso_date?(s)
  cs = if string?(s)
    chars(s)
  else
    []
  end
  length(cs) == 10 and cs[4] == "-" and cs[7] == "-"
end

@doc """
before?: True when date string `a` sorts strictly before `b`.

    before?("2026-01-01", "2026-10-24") #=> true
    before?("2026-10-24", "2026-10-24") #=> false
"""
def before?(a, b)
  a != b and sort_keyed((x) -> x, [a, b])[0] == a
end

@doc """
entry_refusal: Why one policy entry is refused, or nil when it stands. `today` is passed
in (YYYY-MM-DD); nil skips the expiry judgement.

    entry_refusal(level("*", :audit, "new gate"), nil) #=> nil
    entry_refusal(level("*", :audit, ""), nil) #=> "gives no why"
"""
def entry_refusal(e, today)
  kind = if map?(e)
    e[:entry]
  end
  why = if map?(e)
    e[:why]
  end
  if kind != :level and kind != :waive
    "is not a level or a waive entry"
  elsif not string?(why) or trim(why) == ""
    "gives no why"
  elsif kind == :level and not string?(e[:scope])
    "names no scope"
  elsif kind == :level and not member?(e[:level], levels)
    "names a level that is not off, audit or enforce"
  elsif kind == :waive and not (string?(e[:name]) and contains?(e[:name], "::"))
    "names no qualified definition"
  elsif kind == :waive and not iso_date?(e[:until])
    "gives no until date (YYYY-MM-DD)"
  elsif kind == :waive and today != nil and before?(e[:until], today)
    "expired on #{e[:until]}"
  end
end

@doc """
settle: Every entry judged alone: a refused entry is listed with its reason and
takes no effect, and its siblings stand.

    length(get(settle([level("*", :audit, "x"), level("*", :loud, "y")], nil), :refused)) #=> 1
"""
def settle(entries, today)
  judged = map((e) -> [e, entry_refusal(e, today)], entries)
  kept = map((j) -> j[0], filter((j) -> j[1].nil?, judged))
  {
    levels: filter((e) -> e[:entry] == :level, kept),
    waivers: filter((e) -> e[:entry] == :waive, kept),
    refused: map(
      (j) -> {entry: j[0], why: j[1]},
      filter((j) -> j[1] != nil, judged)
    )
  }
end

@doc """
level_of: The level a package is held at: its own entry, else the "*" entry, else
enforce. The last matching entry wins.

    level_of(settle([], nil), "q") #=> :enforce
"""
def level_of(settled, package)
  own = filter((e) -> e[:scope] == package, settled[:levels])
  all = filter((e) -> e[:scope] == "*", settled[:levels])
  if own != []
    own[length(own) - 1][:level]
  elsif all != []
    all[length(all) - 1][:level]
  else
    :enforce
  end
end

@doc """
waived?: True when a standing waiver in `settled` names the qualified definition `name`.

    waived?(settle([waive("kazu::clamp", "in review", "2099-01-01")], nil), "kazu::clamp") #=> true
"""
def waived?(settled, name)
  member?(name, map((w) -> w[:name], settled[:waivers]))
end

@doc """
beside: One package's judgement: its level, the untested names no waiver covers,
and the names a waiver covers.

    get(beside(settle([], nil), "kazu", ["kazu::clamp"]), :untested) #=> ["kazu::clamp"]
"""
def beside(settled, package, names)
  {
    package:,
    level: level_of(settled, package),
    untested: filter((n) -> not waived?(settled, n), names),
    waived: filter((n) -> waived?(settled, n), names)
  }
end

@doc """
stale: Waivers that cover no untested name: a stale waiver would hide the next
real gap, so it is a finding of its own.

    length(stale(settle([waive("kazu::clamp", "in review", "2099-01-01")], nil), [])) #=> 1
"""
def stale(settled, names)
  filter((w) -> not member?(w[:name], names), settled[:waivers])
end

@doc """
axis_states: Every state a closed set of axes can take, one map per combination, in axis order. `axes` is `[[name, [variant, …]], …]`.

    length(axis_states([[:a, %i[x y]], [:b, %i[p q r]]])) #=> 6
"""
def axis_states(axes)
  reduce(
    fn(acc, a)
      reduce(
        (out, s) -> append(out, map((v) -> assoc(s, first(a), v), last(a))),
        [],
        acc
      )
    end,
    [{}],
    axes
  )
end

@doc """
variants: The variants one axis of a closed set of axes can take, nil for an axis the set does not name.

    variants([[:a, %i[x y]], [:b, [:p]]], :a) #=> [:x, :y]
    variants([[:a, [:x]]], :z).nil? #=> true
"""
def variants(axes, axis)
  last(first(filter((a) -> first(a) == axis, axes)))
end

@doc """
row_key: A state's row in a decision matrix: its variants in axis order, tab-separated.

    row_key([[:a, %i[x y]], [:b, %i[p q]]], {a: :y, b: :p}) #=> "y\tp"
"""
def row_key(axes, s)
  join(map((a) -> to_s(get(s, first(a))), axes), "\t")
end

@doc """
matrix_header: The header line of a decision matrix: the axis names, then `outcome`.

    matrix_header([[:a, [:x]], [:b, [:p]]]) #=> "a\tb\toutcome"
"""
def matrix_header(axes)
  "#{join(map((a) -> to_s(first(a)), axes), "\t")}\toutcome"
end

@doc """
matrix_text: A decision matrix as text: the header, then one line per state, its row key and `verdict(state)`. Write it to a fixture and gate it with `matrix_findings`; never edit it by hand.

    matrix_text([[:a, %i[x y]]], (s) -> to_s(s[:a]), axis_states([[:a, %i[x y]]])) #=> "a\toutcome\nx\tx\ny\ty\n"
"""
def matrix_text(axes, verdict, states)
  unlines(
    append(
      [matrix_header(axes)],
      map((s) -> "#{row_key(axes, s)}\t#{verdict(s)}", states)
    )
  )
end

@doc """
matrix_rows: The data lines of a matrix text: every non-blank line but the header.

    matrix_rows([[:a, [:x]]], "a\toutcome\n\nx\tok\n") #=> ["x\tok"]
"""
def matrix_rows(axes, text)
  filter(
    (l) -> trim(l) != "" and l != matrix_header(axes),
    split(text, line_break)
  )
end

@doc """
matrix_row: One data line split into its row key and its outcome.

    matrix_row([[:a, [:x]], [:b, [:p]]], "x\tp\tok") #=> ["x\tp", "ok"]
"""
def matrix_row(axes, line)
  fs = split(line, "\t")
  [join(take(length(axes), fs), "\t"), last(fs)]
end

@doc """
matrix_findings: What a committed matrix text gets wrong against `states` and `verdict`: a missing row, a row naming no state, a duplicate row, and a row whose outcome disagrees. An empty list is the all-variants proof.

    matrix_findings([[:a, [:x]]], (_s) -> "ok", "a\toutcome\nx\tok\n", [{a: :x}]) #=> []
"""
def matrix_findings(axes, verdict, text, states)
  rows = map((l) -> matrix_row(axes, l), matrix_rows(axes, text))
  want = reduce((m, s) -> assoc(m, row_key(axes, s), verdict(s)), {}, states)
  seen = reduce((m, r) -> assoc(m, first(r), last(r)), {}, rows)
  missing = map(
    (s) -> [:missing_row, row_key(axes, s)],
    filter((s) -> get(seen, row_key(axes, s)).nil?, states)
  )
  extra = map(
    (r) -> [:row_without_variant, first(r)],
    filter((r) -> get(want, first(r)).nil?, rows)
  )
  wrong = map(
    (r) -> [:decision_disagrees, "#{first(r)}\twant #{get(want, first(r))}"],
    filter(
      (r) -> get(want, first(r)) != nil and get(want, first(r)) != last(r),
      rows
    )
  )
  append(append(append(missing, extra), duplicate_rows(rows)), wrong)
end

@doc """
duplicate_rows: A `[:duplicate_row, key]` finding for every row whose key an earlier row already had.

    duplicate_rows([["x", "a"], ["y", "b"], ["x", "c"]]) #=> [[:duplicate_row, "x"]]
"""
def duplicate_rows(rows)
  last(
    reduce(
      fn(acc, row)
        if get(first(acc), first(row)).nil?
          [assoc(first(acc), first(row), true), last(acc)]
        else
          [first(acc), append(last(acc), [[:duplicate_row, first(row)]])]
        end
      end,
      [{}, []],
      rows
    )
  )
end

@doc """
coverage_names: The definitions no test reached, from the text `blue test --coverage --json` printed: every coverage record's `uncovered` list, in order. Lines that are not a record (the tally) are passed over.

    coverage_names("{\"covered\": 1, \"uncovered\": [\"a::f\"]}\n2 test(s)") #=> ["a::f"]
    coverage_names("{\"arms\": 0, \"uncovered\": [\"a::g\"]}") #=> ["a::g"]
    coverage_names("") #=> []
"""
def coverage_names(text)
  reduce((acc, r) -> append(acc, uncovered(r)), [], coverage_records(text))
end

@doc """
coverage_records: The coverage records in the text `blue test --coverage --json` printed: each line that is a JSON object holding an `uncovered` list, whatever key it starts with.

    size(coverage_records("{\"arms\": 0, \"uncovered\": []}\n1 test(s)")) #=> 1
"""
def coverage_records(text)
  filter(
    (r) -> map?(r) and list?(r["uncovered"]),
    map(json_read, filter((l) -> starts_with?(l, "{"), split(text, line_break)))
  )
end

@doc """
coverage_verdict: One package's verdict under the settled policy and the recorded debt rows (hadome): off, green, red or blind, with the reason. A measurement is `{package:, blind:, names:}`; blind is never green.

    coverage_verdict(settle([level("*", :enforce, "w")], "2026-01-01"), [], {package: "p", blind: false, names: []})[:verdict] #=> :green
    coverage_verdict(settle([level("*", :enforce, "w")], "2026-01-01"), [], {package: "p", blind: true})[:verdict] #=> :red
"""
def coverage_verdict(settled, rows, m)
  pkg = m[:package]
  if m[:blind]
    b = beside(settled, pkg, [])
    if b[:level] == :off
      assoc(b, :verdict, :off)
    elsif b[:level] == :enforce
      assoc(assoc(b, :verdict, :red), :why, "its tests did not run green")
    else
      assoc(assoc(b, :verdict, :blind), :why, "its tests did not run green")
    end
  else
    b = beside(settled, pkg, m[:names])
    n = size(b[:untested])
    j = hadome::judge(rows, "untested", pkg, n)[:verdict]
    grew = j == :grew or j == :unrecorded and n > 0
    waived = map((w) -> w[:name], settled[:waivers])
    arms = filter(
      (a) -> not member?(before_first(a, "#"), waived),
      m[:arms] or []
    )
    na = size(arms)
    ja = hadome::judge(rows, "unbranched", pkg, na)[:verdict]
    branched = ja == :grew or ja == :unrecorded and na > 0
    b = assoc(b, :unbranched, arms)
    whys = append(
      if grew
        [
          "#{to_s(n)} untested beyond the recorded debt: #{join(b[:untested], ", ")}"
        ]
      else
        []
      end,
      if branched
        [
          "#{to_s(na)} untaken arm(s) beyond the recorded debt: #{join(arms, ", ")}"
        ]
      else
        []
      end
    )
    if b[:level] == :off
      assoc(b, :verdict, :off)
    elsif whys != [] and b[:level] == :enforce
      assoc(assoc(b, :verdict, :red), :why, join(whys, "; "))
    else
      assoc(b, :verdict, :green)
    end
  end
end

@doc """
coverage_arms: The arms of decisions no test took, from the text `blue test --coverage --json` printed: every record's `untaken` list (`def#site:arm`), in order; a record from a blue that records no arms holds none.

    coverage_arms("{\"covered\": 1, \"uncovered\": [], \"untaken\": [\"p::f#0:1\"]}") #=> ["p::f#0:1"]
    coverage_arms("{\"covered\": 1, \"uncovered\": []}") #=> []
"""
def coverage_arms(text)
  reduce(
    (acc, r) -> append(acc, r["untaken"] or []),
    [],
    coverage_records(text)
  )
end

@doc """
judge_coverage: The whole judgement over every measured package: each verdict, every refused entry, every stale waiver, the red verdicts, and the measurements a debt record is rendered from. `baseline` is hadome text (`untested: <pkg> <n>` rows); `day` is today as YYYY-MM-DD.

    judge_coverage([level("*", :enforce, "w")], "", [{package: "p", blind: false, names: ["p::f"]}], "2026-01-01")[:red][0][:why] #=> "1 untested beyond the recorded debt: p::f"
"""
def judge_coverage(entries, baseline, measured, day)
  settled = settle(entries, day)
  rows = hadome::parse(baseline)
  verdicts = map((m) -> coverage_verdict(settled, rows, m), measured)
  every_name = reduce(
    fn(acc, m)
      append(
        append(acc, m[:names] or []),
        map((a) -> before_first(a, "#"), m[:arms] or [])
      )
    end,
    [],
    measured
  )
  judged = filter((v) -> v[:verdict] != :off, verdicts)
  {
    verdicts:,
    refused: settled[:refused],
    stale: stale(settled, every_name),
    red: filter((v) -> v[:verdict] == :red, verdicts),
    measurements: map(
      (v) -> {key: v[:package], size: size(v[:untested])},
      judged
    ),
    arm_measurements: map(
      (v) -> {key: v[:package], size: size(v[:unbranched] or [])},
      judged
    )
  }
end

@doc """
coverage_red?: Whether a judgement fails: an enforced red package, a refused entry or a stale waiver.

    coverage_red?({red: [], refused: [], stale: []}) #=> false
"""
def coverage_red?(r)
  r[:red] != [] or r[:refused] != [] or r[:stale] != []
end

@doc """
coverage_report: The lines a judgement prints: each red package, refused entry and stale waiver, then, when debt shrank, the rows to record in `home`.

    coverage_report({red: [], refused: [], stale: [], measurements: []}, "", "x.b") #=> ""
"""
def coverage_report(r, baseline, home)
  lines = append(
    append(
      map((v) -> "❌ #{v[:package]}: #{v[:why]}", r[:red]),
      map((x) -> "❌ entry #{to_s(x[:entry])} #{x[:why]}", r[:refused])
    ),
    map((w) -> "❌ waiver #{w[:name]} covers nothing; remove it", r[:stale])
  )
  rows = hadome::parse(baseline)
  arms = r[:arm_measurements] or []
  down = append(
    hadome::shrunk(rows, "untested", r[:measurements]),
    hadome::shrunk(rows, "unbranched", arms)
  )
  hint = if down == []
    []
  else
    [
      "debt shrank; record it in #{home}:",
      hadome::render("untested", filter((m) -> m[:size] > 0, r[:measurements])),
      hadome::render("unbranched", filter((m) -> m[:size] > 0, arms))
    ]
  end
  join(append(lines, hint), line_break)
end

test "raises? is true for the kind raised and false for no error"
  assert raises?(:oops, () -> raise(:oops, "no")) == true
  assert raises?(:oops, () -> 1 + 1) == false
  assert raises?(:oops, () -> nil) == false
end

test "raises? is false for another kind and never raises for the kind it tests"
  assert raises?(:oops, () -> raise(:other, "no")) == false
  assert raises?(:other, () -> raise(:oops, "no")) == false
  assert raises?(:oops, () -> raise(:oops, "x", {data: {a: 1}})) == true
end

test "raises? sees an error raised deep inside the function"
  deep = () -> map((x) -> raise(:oops, "at #{to_s(x)}"), [1, 2])
  assert raises?(:oops, deep) == true
  assert raises?(:oops, () -> map((x) -> x, [])) == false
end

test "snapshot records with update and then accepts the same value"
  dir = scratch
  assert snapshot({a: [1, 2]}, {name: "first", dir:, update: true}).nil?
  assert read_file(path_join(dir, "first.b")) == unlines(["{a: [1, 2]}"])
  assert snapshot({a: [1, 2]}, {name: "first", dir:}).nil?
  rm_rf(dir)
end

test "snapshot refuses a changed value and names both copies"
  dir = scratch
  snapshot([1, 2, 3], {name: "list", dir:, update: true})
  e = caught(() -> snapshot([1, 2, 4], {name: "list", dir:}))
  assert e.kind == :snapshot_mismatch
  assert e.data.expected == unlines(["[1, 2, 3]"])
  assert e.data.actual == unlines(["[1, 2, 4]"])
  assert contains?(e.message, "differs") == true
  rm_rf(dir)
end

test "snapshot update replaces the stored copy"
  dir = scratch
  snapshot([1], {name: "n", dir:, update: true})
  snapshot([2], {name: "n", dir:, update: true})
  assert read_file(path_join(dir, "n.b")) == unlines(["[2]"])
  assert snapshot([2], {name: "n", dir:}).nil?
  rm_rf(dir)
end

test "snapshot of nothing recorded is a missing snapshot, not a pass"
  dir = scratch
  e = caught(() -> snapshot(1, {name: "absent", dir:}))
  assert e.kind == :snapshot_missing
  assert path_exists(dir) == false
end

test "snapshot tells text from a keyword and from a number"
  dir = scratch
  snapshot("a", {name: "t", dir:, update: true})
  assert read_file(path_join(dir, "t.b")) == unlines(["\"a\""])
  assert raises?(:snapshot_mismatch, () -> snapshot(:a, {name: "t", dir:}))
  assert raises?(:snapshot_mismatch, () -> snapshot(1, {name: "t", dir:}))
  snapshot(nil, {name: "z", dir:, update: true})
  assert read_file(path_join(dir, "z.b")) == line_break
  assert snapshot(nil, {name: "z", dir:}).nil?
  rm_rf(dir)
end

test "snapshot refuses a missing or unsafe name and an unknown option"
  assert raises?(:bad_option, () -> snapshot(1, {dir: "x"}))
  assert raises?(:bad_option, () -> snapshot(1, {name: "", dir: "x"}))
  assert raises?(:bad_option, () -> snapshot(1, {name: "../up", dir: "x"}))
  assert raises?(:bad_option, () -> snapshot(1, {name: 5, dir: "x"}))
  assert raises?(
    :bad_option,
    () -> snapshot(1, {name: "n", dir: "x", fresh: true})
  )
end

test "snapshot defaults its directory to snapshots"
  assert snapshot_path({name: "n"}) == "snapshots/n.b"
  assert snapshot_path({name: "n", dir: "d/e"}) == "d/e/n.b"
end

test "uncovered reads the names no test reached and refuses a record without them"
  rec = {"covered" => 1, "uncovered" => ["p::b"], "total" => 2}
  assert uncovered(rec) == ["p::b"]
  assert uncovered({"uncovered" => []}) == []
  assert raises?(:coverage, () -> uncovered({"covered" => 1}))
  assert raises?(:coverage, () -> uncovered(nil))
end

test "settle keeps good entries and refuses each bad one alone"
  s = settle(
    [
      level("*", :enforce, "on by default"),
      level("p", :loud, "no such level"),
      level("q", :audit, ""),
      waive("p::b", "a process entry", "2026-12-31"),
      waive("b", "unqualified", "2026-12-31"),
      waive("p::c", "no date", "soon"),
      waive("p::d", "old", "2026-01-01"),
      {entry: :other, why: "x"}
    ],
    "2026-10-24"
  )
  assert map((e) -> e[:scope], s[:levels]) == ["*"]
  assert map((e) -> e[:name], s[:waivers]) == ["p::b"]
  assert map((r) -> r[:why], s[:refused]) ==
    [
      "names a level that is not off, audit or enforce",
      "gives no why",
      "names no qualified definition",
      "gives no until date (YYYY-MM-DD)",
      "expired on 2026-01-01",
      "is not a level or a waive entry"
    ]
end

test "a waiver due today still stands, and no today skips expiry"
  assert entry_refusal(waive("p::b", "x", "2026-10-24"), "2026-10-24").nil?
  assert entry_refusal(waive("p::b", "x", "2020-01-01"), nil).nil?
end

test "a package's own level wins over the star, and enforce is the default"
  s = settle([level("*", :audit, "all"), level("p", :off, "p is off")], nil)
  assert level_of(s, "p") == :off
  assert level_of(s, "q") == :audit
  assert level_of(settle([], nil), "q") == :enforce
end

test "beside splits untested names from waived ones, and stale finds idle waivers"
  s = settle(
    [
      waive("p::b", "a reason", "2027-01-01"),
      waive("p::z", "gone", "2027-01-01")
    ],
    "2026-10-24"
  )
  r = beside(s, "p", %w[p::a p::b])
  assert r[:level] == :enforce
  assert r[:untested] == ["p::a"]
  assert r[:waived] == ["p::b"]
  assert map((w) -> w[:name], stale(s, %w[p::a p::b])) == ["p::z"]
end

test "fresh_dir makes a new empty directory each call"
  a = fresh_dir("tesuto-fresh")
  b = fresh_dir("tesuto-fresh")
  assert a != b
  assert is_dir?(a)
  assert ls(a) == []
  rm_rf(a)
  rm_rf(b)
end

test "axis_states is the product of the axes, and an axis with no variants leaves none"
  axes = [[:a, %i[x y]], [:b, %i[p q r]]]
  states = axis_states(axes)
  assert length(states) == 6
  assert first(states) == {a: :x, b: :p}
  assert last(states) == {a: :y, b: :r}
  assert axis_states([[:a, %i[x y]], [:b, []]]) == []
  assert axis_states([]) == [{}]
end

test "a matrix written by matrix_text has no findings, and every kind of wrong row is found"
  axes = [[:a, %i[x y]], [:b, %i[p q]]]
  verdict = fn(s)
    if s[:a] == :x
      "go"
    else
      "stop"
    end
  end
  states = axis_states(axes)
  text = matrix_text(axes, verdict, states)
  assert matrix_header(axes) == "a\tb\toutcome"
  assert length(matrix_rows(axes, text)) == 4
  assert matrix_row(axes, "x\tp\tgo") == ["x\tp", "go"]
  assert row_key(axes, {a: :y, b: :q}) == "y\tq"
  assert matrix_findings(axes, verdict, text, states) == []
  short = unlines(append([matrix_header(axes)], rest(matrix_rows(axes, text))))
  assert matrix_findings(axes, verdict, short, states) ==
    [[:missing_row, "x\tp"]]
  stray = concat(text, unlines(["z\tp\tgo"]))
  assert matrix_findings(axes, verdict, stray, states) ==
    [[:row_without_variant, "z\tp"]]
  twice = concat(text, unlines(["x\tp\tgo"]))
  assert matrix_findings(axes, verdict, twice, states) ==
    [[:duplicate_row, "x\tp"]]
  flipped = replace(text, "y\tq\tstop", "y\tq\tgo")
  assert matrix_findings(axes, verdict, flipped, states) ==
    [[:decision_disagrees, "y\tq\twant stop"]]
  assert duplicate_rows([]) == []
end
