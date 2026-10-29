@moduledoc """
okite (掟) — blue's decisions, each enforced by laws written in blue.

Every decision about how blue behaves is a record in `ok_decisions()`: an id,
the date, the rule in one line, why, and the laws that enforce it. A law is a
blue function that returns true when the rule holds; the generative ones hold
it over hundreds of seeded values, not just the cases someone thought of. The
tests at the bottom fail the build when a decision has no law or a law fails,
and RULES.md, the card a person or a model reads to learn blue, is generated
from the same records (rules.b), so the card and the enforcement cannot drift.

The meta-rule the card starts with: blue values behave like Ruby's, except
where a decision here records a deviation. Knowing Ruby is knowing blue.

    failures #=> []
"""

use("junjo", [:sort])
use("kyohi")
use("moji", [:lines])
use("ran", %i[next_bool next_seed next_uniform pick])
use("retsu", %i[contains first flat_map index_of is_empty rest size])

legacy_names("0.1.1", "ok")

# ── generated values ───────────────────────────────────────────────────────
#
# `ok_gen(seed, depth)` is `[value, next_seed]`: an int, a float (integral or
# a half), a string, nil, a bool, or, while depth allows, a list or a map with
# keyword keys. Seeded, so every run checks the same values and a failure
# reproduces.

def gen(seed, depth)
  kinds = kind_count(depth)
  gen_kind(next_uniform(seed, kinds), next_seed(seed), depth)
end

def kind_count(depth)
  if depth > 0
    7
  else
    5
  end
end

def gen_kind(k, s, depth)
  if k == 0
    [next_uniform(s, 100) - 50, next_seed(s)]
  elsif k == 1
    [to_float(next_uniform(s, 100) - 50) + half(s), next_seed(next_seed(s))]
  else
    gen_kind_more(k, s, depth)
  end
end

def gen_kind_more(k, s, depth)
  if k == 2
    [pick(s, ["", "a", "b", "ab", "x y", "日本"]), next_seed(s)]
  elsif k == 3
    [nil, s]
  else
    gen_kind_rest(k, s, depth)
  end
end

def gen_kind_rest(k, s, depth)
  if k == 4
    [next_bool(s), next_seed(s)]
  elsif k == 5
    gen_list(next_seed(s), next_uniform(s, 4), depth - 1, [])
  else
    gen_map(next_seed(s), next_uniform(s, 4), depth - 1, {})
  end
end

def half(s)
  if next_bool(next_seed(s))
    0.5
  else
    0.0
  end
end

def gen_list(s, n, depth, acc)
  if n < 1
    [reverse(acc), s]
  else
    g = gen(s, depth)
    gen_list(g[1], n - 1, depth, cons(g[0], acc))
  end
end

def gen_map(s, n, depth, acc)
  if n < 1
    [acc, s]
  else
    g = gen(next_seed(s), depth)
    key = pick(s, %i[a b c d])
    gen_map(g[1], n - 1, depth, assoc(acc, key, g[0]))
  end
end

@doc """
values: `n` generated values from `seed`, each up to two levels deep.
"""
def values(seed, n)
  values_from(seed, n, [])
end

def values_from(s, n, acc)
  if n < 1
    reverse(acc)
  else
    g = gen(s, 2)
    values_from(g[1], n - 1, cons(g[0], acc))
  end
end

@doc """
pairs: Consecutive pairs of generated values, so pairs mix kinds.
"""
def pairs(seed, n)
  vs = values(seed, n + 1)
  map((i) -> [vs[i], vs[i + 1]], range(0, n))
end

def all(f, xs)
  is_empty(filter((x) -> not f(x), xs))
end

# ── laws ───────────────────────────────────────────────────────────────────

def law_equal_reflexive()
  all((v) -> v == v, values(11, 300))
end

def law_equal_symmetric()
  all((p) -> p[0] == p[1] == (p[1] == p[0]), pairs(12, 300))
end

def law_not_equal_is_negation()
  all(
    fn(p)
      same = p[0] == p[1]
      p[0] != p[1] == (not same)
    end,
    pairs(13, 300)
  )
end

def law_numbers_by_value()
  ns = map((i) -> i - 20, range(0, 41))
  all((n) -> n == to_float(n) and to_float(n) == n and n != n + 0.5, ns) and
    4 == 4.0 and
    [1, 2] == [1.0, 2.0]
end

def law_maps_by_value()
  a = assoc(assoc({}, :a, 1), :b, [2, "x"])
  b = assoc(assoc({}, :b, [2, "x"]), :a, 1)
  a == b and
    {a: 1} == {a: 1} and
    {a: 1} != {a: 2} and
    {a: 1} != {b: 1} and
    {a: 1} != {a: 1, b: 2} and
    {} == {}
end

def law_nil_is_not_empty_list()
  nil != [] and [] == [] and nil == nil and is_empty(nil) and is_empty([])
end

def law_membership_is_equality()
  pairs = okite::pairs(14, 200)
  all((p) -> contains([p[0]], p[1]) == (p[0] == p[1]), pairs) and
    contains([1], 1.0) and
    index_of([{a: 1}], {a: 1}) == 0
end

def law_to_s_literals()
  to_s(3) == "3" and
    to_s(1.0) == "1.0" and
    to_s(2.5) == "2.5" and
    to_s(true) == "true" and
    "a b" == "a b" and
    to_s(nil) == ""
end

def law_to_s_collections()
  to_s([]) == "[]" and
    to_s({}) == "{}" and
    to_s([1, "a", nil, 2.0]) == "[1, \"a\", nil, 2.0]" and
    to_s({b: 2, a: [1]}) == "{a: [1], b: 2}"
end

def law_to_s_equal_maps_render_equally()
  a = assoc(assoc(assoc({}, :c, 3), :a, 1), :b, 2)
  b = assoc(assoc(assoc({}, :b, 2), :c, 3), :a, 1)
  to_s(a) == to_s(b) and "#{[1, 2]}" == "[1, 2]"
end

def law_concat_any_arity()
  ss = ["", "a", "bc", "日本", "x y"]
  triples = map(
    (i) -> [ss[i % 5], ss[(i + 1) % 5], ss[(i + 3) % 5]],
    range(0, 25)
  )
  all(
    (t) -> concat(t[0], t[1], t[2]) == concat(concat(t[0], t[1]), t[2]),
    triples
  ) and concat("a") == "a" and concat("a", "b", "c", "d") == "abcd"
end

def law_division_is_float()
  7 / 2 == 3.5 and 4 / 2 == 2 and 1 / 4 == 0.25
end

# waive B0036: the law states what nil? and bool? themselves answer
def kinds(v)
  [
    v.nil?,
    bool?(v),
    integer?(v),
    float?(v),
    string?(v),
    keyword?(v),
    list?(v),
    map?(v)
  ]
end

def law_one_kind_each()
  all((v) -> size(filter((k) -> k, kinds(v))) == 1, values(15, 300)) and
    not list?(nil) and
    not [].nil?
end

# waive B0036: the law states what cdr and nil? themselves answer
def law_empty_list_is_brackets()
  results = [
    rest([1]),
    cdr([1]),
    append([], []),
    append(),
    filter((_x) -> false, [1]),
    map((x) -> x, []),
    reverse([]),
    take(0, [1]),
    drop(1, [1]),
    range(0, 0),
    split("", ""),
    sort([]),
    distinct([]),
    flat_map([1], (_x) -> [])
  ]
  all((r) -> r == [] and not r.nil?, results)
end

def law_split_keeps_every_field()
  seps = [",", "|", line_break, "ab"]
  words = ["", "a", "x y", "日本", "a,b", "|", "abab"]
  cases = map(
    fn(i)
      [seps[i % 4], [words[i % 7], words[(i + 2) % 7], words[(i + 5) % 7]]]
    end,
    range(0, 56)
  )
  all(
    (c) -> join(split(join(c[1], c[0]), c[0]), c[0]) == join(c[1], c[0]),
    cases
  ) and
    split("", ",") ==
      [""] and
    split("a,b,,", ",") == ["a", "b", "", ""] and size(split(",,", ",")) == 3
end

def law_map_keys_are_exact()
  m = assoc({}, 1, :int)
  get(m, 1) == :int and get(m, 1.0).nil?
end

@doc """
law_string_is_not_keyword: a string and a keyword of the same text are different values and different map keys.

    law_string_is_not_keyword #=> true
"""
def law_string_is_not_keyword()
  "a" != :a and {"a" => 1} != {a: 1} and {a: 1}["a"].nil?
end

@doc """
law_text_names_take_either: a word that reads a name (`json_get`, `json_get_or`, `error`) takes the string or the keyword alike.

    law_text_names_take_either #=> true
"""
def law_text_names_take_either()
  doc = json_parse("{\"a\": 1}")
  key = "a"
  kind = "bad"
  json_get(doc, key) == json_get(doc, :a) and
    json_get_or(doc, key, 0) == json_get_or(doc, :a, 0) and
    error(kind, "m").kind == error(:bad, "m").kind
end

def chain_values()
  fixed = [
    "",
    "a",
    " a ",
    "007",
    "1.5",
    "-3",
    "1e3",
    " 12 ",
    "日本",
    "\"q\"",
    join_lines(%w[a b]),
    "ẞ",
    "İ",
    "x y",
    0,
    1,
    -1,
    42,
    9_007_199_254_740_993,
    -9_007_199_254_740_993,
    0.0,
    1.5,
    -2.5,
    1000000.0,
    0.1,
    :a,
    :ok,
    nil,
    true,
    false,
    [],
    [1, "a"],
    {a: 1},
    {}
  ]
  append(fixed, values(41, 200))
end

def chain_kind_matches(kind, v)
  if kind.nil?
    true
  elsif kind == :text
    string?(v)
  elsif kind == :int
    integer?(v)
  else
    float?(v)
  end
end

def chain_outcome(f, v)
  [:value, f(v)]
rescue e
  [:refused, e.kind]
end

def chain_same_result(x, y)
  if float?(x) or float?(y)
    float?(x) and float?(y) and to_s(x) == to_s(y)
  else
    x == y and integer?(x) == integer?(y) and string?(x) == string?(y)
  end
end

def chain_same(a, b)
  a[0] == b[0] and chain_same_result(a[1], b[1])
end

def chain_case_values(c)
  filter((v) -> chain_kind_matches(c[1], v), chain_values)
end

def chain_check(label, kind, lhs, rhs)
  bad = filter(
    (v) -> not chain_same(chain_outcome(lhs, v), chain_outcome(rhs, v)),
    filter((v) -> chain_kind_matches(kind, v), chain_values)
  )
  map(
    fn(v)
      "#{label} on #{v}: #{chain_outcome(lhs, v)} vs #{chain_outcome(rhs, v)}"
    end,
    bad
  )
end

def chain_case_counterexamples(c)
  chain_check(c[0], c[1], eval(c[2]), eval(c[3]))
end

def chain_counterexamples(rule)
  flat_map(rule[4], chain_case_counterexamples)
end

def chain_covered(rule)
  all((c) -> size(chain_case_values(c)) >= 10, rule[4])
end

def chain_rule_holds(rule)
  chain_covered(rule) and is_empty(chain_counterexamples(rule))
end

def chain_law(rule)
  [
    "#{rule[0]} #{rule[1]}",
    () -> chain_rule_holds(rule),
    () -> chain_counterexamples(rule)
  ]
end

# ── the raising form of a check ────────────────────────────────────────────

def refusal_lists_from(s, n, acc)
  if n < 1
    reverse(acc)
  else
    count = next_uniform(s, 4)
    refusals = map(
      fn(i)
        kyohi::refusal(
          pick(next_seed(s) + i, %i[a b c]),
          pick(next_seed(next_seed(s)) + i, ["", "x", "x y", "日本"])
        )
      end,
      range(0, count)
    )
    refusal_lists_from(next_seed(next_seed(s)), n - 1, cons(refusals, acc))
  end
end

def refuse_outcome(rs)
  if is_empty(rs)
    [:value, nil, nil]
  else
    [:refused, kyohi::kind(first(rs)), join(map(kyohi::why, rs), "; ")]
  end
end

def enforce_outcome(rs)
  kyohi::enforce(rs, [(r) -> r], {kind: :first})
  [:value, nil, nil]
rescue e
  [:refused, e.kind, e.message]
end

def law_enforce_is_the_old_refuse()
  fixed = [
    [],
    [kyohi::refusal(:a, "one")],
    [kyohi::refusal(:b, "two"), kyohi::refusal(:a, "one")],
    [kyohi::refusal(:a, ""), kyohi::refusal(:a, "")]
  ]
  cases = append(fixed, refusal_lists_from(77, 120, []))
  all((rs) -> enforce_outcome(rs) == refuse_outcome(rs), cases) and
    some((rs) -> size(rs) > 1, cases) and
    some((rs) -> is_empty(rs), cases)
end

# ── the ledger ─────────────────────────────────────────────────────────────

def decisions()
  [
    {
      id: "D0001",
      date: "2026-09-27",
      rule: "`==` is value equality: numbers by value (4 == 4.0), strings, lists and maps by content, nil only equals nil.",
      why: "Ruby's answer; maps compared by identity and 4 != 4.0 were silent wrong answers.",
      laws: [
        ["reflexive", () -> law_equal_reflexive],
        ["symmetric", () -> law_equal_symmetric],
        ["numbers by value", () -> law_numbers_by_value],
        ["maps by value", () -> law_maps_by_value]
      ]
    },
    {
      id: "D0002",
      date: "2026-09-27",
      rule: "`!=` is exactly `not(a == b)`.",
      why: "Two operators, one meaning.",
      laws: [["negation", () -> law_not_equal_is_negation]]
    },
    {
      id: "D0003",
      date: "2026-09-27",
      rule: "`contains`, `index_of`, `count_of` and `distinct` use `==`.",
      why: "Membership that disagrees with equality answers the same question two ways.",
      laws: [["membership", () -> law_membership_is_equality]]
    },
    {
      id: "D0004",
      date: "2026-09-27",
      rule: "`nil` and `[]` are different values; `is_empty` is true of both.",
      why: "Ruby: absent is not empty.",
      laws: [["nil is not []", () -> law_nil_is_not_empty_list]]
    },
    {
      id: "D0005",
      date: "2026-09-27",
      rule: "`to_s` gives text: a string is itself, nil is \"\", a float keeps its point (1.0).",
      why: "Ruby's to_s; to_s(1.0) was \"1\".",
      laws: [["literals", () -> law_to_s_literals]]
    },
    {
      id: "D0006",
      date: "2026-09-27",
      rule: "A list or map renders as its blue literal, maps sorted by key: [1, \"a\"], {a: 1}. Interpolation uses to_s.",
      why: "to_s of a map was the word \"map\" and a list lost its brackets.",
      laws: [
        ["collections", () -> law_to_s_collections],
        ["equal maps render equally", () -> law_to_s_equal_maps_render_equally]
      ]
    },
    {
      id: "D0007",
      date: "2026-09-27",
      rule: "`concat` joins the text of one or more arguments, left to right.",
      why: "Ruby's String#concat takes many; two-only was an arity error.",
      laws: [["any arity", () -> law_concat_any_arity]]
    },
    {
      id: "D0008",
      date: "2026-09-27",
      rule: "`/` is float division (7 / 2 == 3.5). Deviation from Ruby, kept.",
      why: "Integer truncation by the division operator is a classic silent bug.",
      laws: [["float division", () -> law_division_is_float]]
    },
    {
      id: "D0009",
      date: "2026-09-27",
      rule: "Map keys are exact: 1 and 1.0 are different keys.",
      why: "Ruby hashes key on eql?, where 1 and 1.0 differ.",
      laws: [["exact keys", () -> law_map_keys_are_exact]]
    },
    {
      id: "D0010",
      date: "2026-09-27",
      rule: "Every value has exactly one kind, each with one predicate: nil?, bool?, integer?, float?, string?, keyword?, list?, map?.",
      why: "float?, map? and bool? did not exist; nil? and list? each also held of the other kind.",
      laws: [["one kind each", () -> law_one_kind_each]]
    },
    {
      id: "D0011",
      date: "2026-09-27",
      rule: "The empty list is always []: no list operation returns nil for an empty result.",
      why: "rest, cdr and append returned nil (Scheme), so rest([1]) == [] was false.",
      laws: [["empty is []", () -> law_empty_list_is_brackets]]
    },
    {
      id: "D0012",
      date: "2026-09-27",
      rule: "`split` keeps every field: n separators give n + 1 fields, and join undoes split. Deviation from Ruby.",
      why: "Ruby drops trailing empty fields; tried, it broke nisshi, kueri and moji: a parser that loses a field loses data.",
      laws: [["join undoes split", () -> law_split_keeps_every_field]]
    },
    {
      id: "D0013",
      date: "2026-10-21",
      rule: "A conversion chain is simplified only by a row of chain_rules, and a row gives the chain's own value, or its refusal, for every value.",
      why: "to_s(to_s(x)) is to_s(x), but to_int(to_int(x)) is not to_int(x); the check stage, the formatter and the evaluator read one table, and every row carries a law.",
      laws: map(chain_law, chain_rules)
    },
    {
      id: "D0014",
      date: "2026-10-23",
      rule: "`kyohi::check` returns every finding and never raises; `kyohi::enforce` raises them as one error: kind from opts (`:first` or `:refused`), whys joined.",
      why: "`kyohi::refuse` raised and returned nil, which is the enforce meaning under the name the master check contract gives to the list; its callers now call enforce with `kind: :first` and raise what they raised.",
      laws: [["enforce is the old refuse", () -> law_enforce_is_the_old_refuse]]
    },
    {
      id: "D0015",
      date: "2026-10-28",
      rule: "A string and a keyword are different values (\"a\" != :a); error, json_get and json_get_or read either as text, and there a name is a keyword.",
      why: "The operator: symbols where possible, a character shorter and interned; B0067 respells only where a builtin reads the two alike, and a conformance row proves each such position.",
      laws: [
        ["a string is not a keyword", () -> law_string_is_not_keyword],
        ["text names take either", () -> law_text_names_take_either]
      ]
    }
  ]
end

@doc """
holds: A law holds when it returns true. One that throws does not hold: it is
reported by its decision like any other failure, never aborting the check.
"""
def holds(law)
  law(*[]) == true rescue false
end

@doc """
failures: Every law that does not hold, as "id: law", and every decision with no law.

    failures #=> []
"""
def failures()
  flat_map(decisions, decision_failures)
end

def decision_failures(d)
  laws = d[:laws]
  if is_empty(laws)
    ["#{d[:id]}: has no law"]
  else
    map(
      (l) -> "#{d[:id]}: #{l[0]}#{law_why(l)}",
      filter((l) -> not holds(l[1]), laws)
    )
  end
end

def law_why(l)
  if size(l) > 2
    why = l[2]
    " (#{join(take(3, why(*[])), "; ")})"
  else
    ""
  end
end

# ── the card ───────────────────────────────────────────────────────────────
#
# RULES.md, the whole of what a person or a model must learn to write blue
# beyond Ruby, rendered from the ledger (rules.b writes it; the root Bluefile
# declares it generated, so a stale card is a red build).

def card_line(d)
  unlines(["- **#{d[:id]}** #{d[:rule]}"])
end

def card()
  head = unlines(
    [
      "# Blue's rules",
      "",
      "Generated from `bidamas/okite/okite.b` by `rules.b`: do not edit.",
      "Every rule is enforced by laws in okite; a rule without a passing law fails",
      "the build.",
      "",
      "**Blue values behave like Ruby's, except where a rule below says otherwise.**",
      ""
    ]
  )
  concat(head, join(map(card_line, decisions), ""))
end

# ── tests ──────────────────────────────────────────────────────────────────

test "every decision is enforced, and every law holds"
  assert failures == []
end

test "decision ids are unique and in order"
  ids = map((d) -> d[:id], decisions)
  assert ids == distinct(ids)
  assert ids == sort(ids)
end

test "the card stays small: a rule is a line, and the card fits in 40"
  card = okite::card
  assert size(lines(card)) <= 40
  assert all((d) -> length(d[:rule]) <= 160, decisions)
end

test "the generator covers every kind (anti-vacuity)"
  vs = values(99, 300)
  assert some((v) -> integer?(v), vs)
  assert some((v) -> float?(v), vs)
  assert some((v) -> string?(v), vs)
  assert some((v) -> v.nil?, vs)
  assert some((v) -> list?(v) and not is_empty(v), vs)
  assert some((v) -> map?(v), vs)
end

test "every row of the chain table has a law, and each law reaches values"
  laws = map(chain_law, chain_rules)
  assert size(laws) == size(chain_rules)
  assert size(chain_rules) >= 6
  assert all(chain_covered, chain_rules)
  assert all((l) -> holds(l[1]), laws)
end

test "the chain values cover every kind a conversion can see"
  vs = chain_values
  assert some((v) -> v == "", vs)
  assert some((v) -> v == "007", vs)
  assert some((v) -> keyword?(v), vs)
  assert some((v) -> v.nil?, vs)
  assert some((v) -> float?(v), vs)
  assert some((v) -> integer?(v), vs)
  assert some((v) -> list?(v), vs)
  assert some((v) -> map?(v), vs)
end

test "a chain law names the value that breaks an unsound identity"
  bad = chain_check(
    "to_int twice",
    nil,
    (x) -> to_int(to_int(x)),
    (x) -> to_int(x)
  )
  assert not is_empty(bad)
  assert some((s) -> contains?(s, "refused"), bad)
end
