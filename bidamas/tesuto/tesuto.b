@moduledoc """
tesuto (テスト) — testing: errors and snapshots as assertions, and the policy that holds every definition to a test beside it.

    uncovered({"uncovered" => []}) #=> []
"""

use("moji", [:checked, :trim])

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

def snapshot_path(opts)
  name = get(opts, :name)
  if not string?(name) or name == "" or contains?(name, "/")
    raise(:bad_option, "a snapshot takes name: text with no slash")
  end
  path_join(get(opts, :dir) or "snapshots", "#{name}.b")
end

@doc """
snapshot: compare a value with its stored copy; update on request.
"""
def snapshot(value, opts)
  checked(opts, [:name, :dir, :update])
  path = snapshot_path(opts)
  actual = "#{literal(value)}\n"
  if get(opts, :update) == true
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
        "snapshot #{path} differs\nexpected: #{expected}actual:   #{actual}",
        {data: {path:, expected:, actual:}}
      )
    end
    nil
  end
end

def scratch()
  path_join(getenv("TMPDIR") or "/tmp", "tesuto-#{to_s(now_ns)}")
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
    get(coverage, "uncovered")
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
  [:off, :audit, :enforce]
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
  length(cs) == 10 and nth(4, cs) == "-" and nth(7, cs) == "-"
end

@doc """
before?: True when date string `a` sorts strictly before `b`.

    before?("2026-01-01", "2026-10-24") #=> true
    before?("2026-10-24", "2026-10-24") #=> false
"""
def before?(a, b)
  a != b and nth(0, sort_keyed((x) -> x, [a, b])) == a
end

@doc """
entry_refusal: Why one policy entry is refused, or nil when it stands. `today` is passed
in (YYYY-MM-DD); nil skips the expiry judgement.

    entry_refusal(level("*", :audit, "new gate"), nil) #=> nil
    entry_refusal(level("*", :audit, ""), nil) #=> "gives no why"
"""
def entry_refusal(e, today)
  kind = if map?(e)
    get(e, :entry)
  end
  why = if map?(e)
    get(e, :why)
  end
  if kind != :level and kind != :waive
    "is not a level or a waive entry"
  elsif not string?(why) or trim(why) == ""
    "gives no why"
  elsif kind == :level and not string?(get(e, :scope))
    "names no scope"
  elsif kind == :level and not member?(get(e, :level), levels)
    "names a level that is not off, audit or enforce"
  elsif kind == :waive and
      not (string?(get(e, :name)) and contains?(get(e, :name), "::"))
    "names no qualified definition"
  elsif kind == :waive and not iso_date?(get(e, :until))
    "gives no until date (YYYY-MM-DD)"
  elsif kind == :waive and today != nil and before?(get(e, :until), today)
    "expired on #{get(e, :until)}"
  end
end

@doc """
settle: Every entry judged alone: a refused entry is listed with its reason and
takes no effect, and its siblings stand.

    length(get(settle([level("*", :audit, "x"), level("*", :loud, "y")], nil), :refused)) #=> 1
"""
def settle(entries, today)
  judged = map((e) -> [e, entry_refusal(e, today)], entries)
  kept = map((j) -> nth(0, j), filter((j) -> nth(1, j).nil?, judged))
  {
    levels: filter((e) -> get(e, :entry) == :level, kept),
    waivers: filter((e) -> get(e, :entry) == :waive, kept),
    refused: map(
      (j) -> {entry: nth(0, j), why: nth(1, j)},
      filter((j) -> nth(1, j) != nil, judged)
    )
  }
end

@doc """
level_of: The level a package is held at: its own entry, else the "*" entry, else
enforce. The last matching entry wins.

    level_of(settle([], nil), "q") #=> :enforce
"""
def level_of(settled, package)
  own = filter((e) -> get(e, :scope) == package, get(settled, :levels))
  all = filter((e) -> get(e, :scope) == "*", get(settled, :levels))
  if own != []
    get(nth(length(own) - 1, own), :level)
  elsif all != []
    get(nth(length(all) - 1, all), :level)
  else
    :enforce
  end
end

@doc """
waived?: True when a standing waiver in `settled` names the qualified definition `name`.

    waived?(settle([waive("kazu::clamp", "in review", "2099-01-01")], nil), "kazu::clamp") #=> true
"""
def waived?(settled, name)
  member?(name, map((w) -> get(w, :name), get(settled, :waivers)))
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
  filter((w) -> not member?(get(w, :name), names), get(settled, :waivers))
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
  assert read_file(path_join(dir, "first.b")) == "{a: [1, 2]}\n"
  assert snapshot({a: [1, 2]}, {name: "first", dir:}).nil?
  rm_rf(dir)
end

test "snapshot refuses a changed value and names both copies"
  dir = scratch
  snapshot([1, 2, 3], {name: "list", dir:, update: true})
  e = caught(() -> snapshot([1, 2, 4], {name: "list", dir:}))
  assert e.kind == :snapshot_mismatch
  assert e.data.expected == "[1, 2, 3]\n"
  assert e.data.actual == "[1, 2, 4]\n"
  assert contains?(e.message, "differs") == true
  rm_rf(dir)
end

test "snapshot update replaces the stored copy"
  dir = scratch
  snapshot([1], {name: "n", dir:, update: true})
  snapshot([2], {name: "n", dir:, update: true})
  assert read_file(path_join(dir, "n.b")) == "[2]\n"
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
  assert read_file(path_join(dir, "t.b")) == "\"a\"\n"
  assert raises?(:snapshot_mismatch, () -> snapshot(:a, {name: "t", dir:}))
  assert raises?(:snapshot_mismatch, () -> snapshot(1, {name: "t", dir:}))
  snapshot(nil, {name: "z", dir:, update: true})
  assert read_file(path_join(dir, "z.b")) == "\n"
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
  assert map((e) -> get(e, :scope), get(s, :levels)) == ["*"]
  assert map((e) -> get(e, :name), get(s, :waivers)) == ["p::b"]
  assert map((r) -> get(r, :why), get(s, :refused)) ==
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
  r = beside(s, "p", ["p::a", "p::b"])
  assert get(r, :level) == :enforce
  assert get(r, :untested) == ["p::a"]
  assert get(r, :waived) == ["p::b"]
  assert map((w) -> get(w, :name), stale(s, ["p::a", "p::b"])) == ["p::z"]
end
