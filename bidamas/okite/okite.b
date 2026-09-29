use("retsu")
use("moji")
use("ran")

# okite (掟) — blue's decisions, each enforced by laws written in blue.
#
# Every decision about how blue behaves is a record in `ok_decisions()`: an id,
# the date, the rule in one line, why, and the laws that enforce it. A law is a
# blue function that returns true when the rule holds; the generative ones hold
# it over hundreds of seeded values, not just the cases someone thought of. The
# tests at the bottom fail the build when a decision has no law or a law fails,
# and RULES.md, the card a person or a model reads to learn blue, is generated
# from the same records (rules.b), so the card and the enforcement cannot drift.
#
# The meta-rule the card starts with: blue values behave like Ruby's, except
# where a decision here records a deviation. Knowing Ruby is knowing blue.

# ── generated values ───────────────────────────────────────────────────────
#
# `ok_gen(seed, depth)` is `[value, next_seed]`: an int, a float (integral or
# a half), a string, nil, a bool, or, while depth allows, a list or a map with
# keyword keys. Seeded, so every run checks the same values and a failure
# reproduces.

def ok_gen(seed, depth)
  kinds = ok_kind_count(depth)
  ok_gen_kind(next_uniform(seed, kinds), next_seed(seed), depth)
end

def ok_kind_count(depth)
  if depth > 0
    7
  else
    5
  end
end

def ok_gen_kind(k, s, depth)
  if k == 0
    [next_uniform(s, 100) - 50, next_seed(s)]
  elsif k == 1
    [to_float(next_uniform(s, 100) - 50) + ok_half(s), next_seed(next_seed(s))]
  else
    ok_gen_kind_more(k, s, depth)
  end
end

def ok_gen_kind_more(k, s, depth)
  if k == 2
    [pick(s, ["", "a", "b", "ab", "x y", "日本"]), next_seed(s)]
  elsif k == 3
    [nil, s]
  else
    ok_gen_kind_rest(k, s, depth)
  end
end

def ok_gen_kind_rest(k, s, depth)
  if k == 4
    [next_bool(s), next_seed(s)]
  elsif k == 5
    ok_gen_list(next_seed(s), next_uniform(s, 4), depth - 1, [])
  else
    ok_gen_map(next_seed(s), next_uniform(s, 4), depth - 1, {})
  end
end

def ok_half(s)
  if next_bool(next_seed(s))
    0.5
  else
    0.0
  end
end

def ok_gen_list(s, n, depth, acc)
  if n < 1
    [reverse(acc), s]
  else
    g = ok_gen(s, depth)
    ok_gen_list(nth(1, g), n - 1, depth, cons(nth(0, g), acc))
  end
end

def ok_gen_map(s, n, depth, acc)
  if n < 1
    [acc, s]
  else
    g = ok_gen(next_seed(s), depth)
    key = pick(s, [:a, :b, :c, :d])
    ok_gen_map(nth(1, g), n - 1, depth, assoc(acc, key, nth(0, g)))
  end
end

# `n` generated values from `seed`, each up to two levels deep.
def ok_values(seed, n)
  ok_values_from(seed, n, [])
end

def ok_values_from(s, n, acc)
  if n < 1
    reverse(acc)
  else
    g = ok_gen(s, 2)
    ok_values_from(nth(1, g), n - 1, cons(nth(0, g), acc))
  end
end

# Consecutive pairs of generated values, so pairs mix kinds.
def ok_pairs(seed, n)
  vs = ok_values(seed, n + 1)
  map(fn(i) [nth(i, vs), nth(i + 1, vs)] end, range(0, n))
end

def ok_all(f, xs)
  is_empty(filter(fn(x) !f(x) end, xs))
end

# ── laws ───────────────────────────────────────────────────────────────────

def ok_law_equal_reflexive()
  ok_all(fn(v) v == v end, ok_values(11, 300))
end

def ok_law_equal_symmetric()
  ok_all(
    fn(p) nth(0, p) == nth(1, p) == (nth(1, p) == nth(0, p)) end,
    ok_pairs(12, 300)
  )
end

def ok_law_not_equal_is_negation()
  ok_all(
    fn(p) nth(0, p) != nth(1, p) == !(nth(0, p) == nth(1, p)) end,
    ok_pairs(13, 300)
  )
end

def ok_law_numbers_by_value()
  ns = map(fn(i) i - 20 end, range(0, 41))
  ok_all(fn(n) n == to_float(n) && to_float(n) == n && n != n + 0.5 end, ns) &&
    4 == 4.0 &&
    [1, 2] == [1.0, 2.0]
end

def ok_law_maps_by_value()
  a = assoc(assoc({}, :a, 1), :b, [2, "x"])
  b = assoc(assoc({}, :b, [2, "x"]), :a, 1)
  a == b &&
    {a: 1} == {a: 1} &&
    {a: 1} != {a: 2} &&
    {a: 1} != {b: 1} &&
    {a: 1} != {a: 1, b: 2} &&
    {} == {}
end

def ok_law_nil_is_not_empty_list()
  nil != [] && [] == [] && nil == nil && is_empty(nil) && is_empty([])
end

def ok_law_membership_is_equality()
  pairs = ok_pairs(14, 200)
  ok_all(
    fn(p) contains([nth(0, p)], nth(1, p)) == (nth(0, p) == nth(1, p)) end,
    pairs
  ) &&
    contains([1], 1.0) &&
    index_of([{a: 1}], {a: 1}) == 0
end

def ok_law_to_s_literals()
  to_s(3) == "3" &&
    to_s(1.0) == "1.0" &&
    to_s(2.5) == "2.5" &&
    to_s(true) == "true" &&
    to_s("a b") == "a b" &&
    to_s(nil) == ""
end

def ok_law_to_s_collections()
  to_s([]) == "[]" &&
    to_s({}) == "{}" &&
    to_s([1, "a", nil, 2.0]) == "[1, \"a\", nil, 2.0]" &&
    to_s({b: 2, a: [1]}) == "{a: [1], b: 2}"
end

def ok_law_to_s_equal_maps_render_equally()
  a = assoc(assoc(assoc({}, :c, 3), :a, 1), :b, 2)
  b = assoc(assoc(assoc({}, :b, 2), :c, 3), :a, 1)
  to_s(a) == to_s(b) && "#{[1, 2]}" == "[1, 2]"
end

def ok_law_concat_any_arity()
  ss = ["", "a", "bc", "日本", "x y"]
  triples = map(
    fn(i) [nth(i % 5, ss), nth((i + 1) % 5, ss), nth((i + 3) % 5, ss)] end,
    range(0, 25)
  )
  ok_all(
    fn(t)
      concat(nth(0, t), nth(1, t), nth(2, t)) ==
        concat(concat(nth(0, t), nth(1, t)), nth(2, t))
    end,
    triples
  ) &&
    concat("a") == "a" &&
    concat("a", "b", "c", "d") == "abcd"
end

def ok_law_division_is_float()
  7 / 2 == 3.5 && 4 / 2 == 2 && 1 / 4 == 0.25
end

def ok_kinds(v)
  [
    nil?(v),
    bool?(v),
    integer?(v),
    float?(v),
    string?(v),
    keyword?(v),
    list?(v),
    map?(v)
  ]
end

def ok_law_one_kind_each()
  ok_all(
    fn(v) size(filter(fn(k) k end, ok_kinds(v))) == 1 end,
    ok_values(15, 300)
  ) &&
    !list?(nil) &&
    !nil?([])
end

def ok_law_empty_list_is_brackets()
  results = [
    rest([1]),
    cdr([1]),
    append([], []),
    append(),
    filter(fn(_x) false end, [1]),
    map(fn(x) x end, []),
    reverse([]),
    take(0, [1]),
    drop(1, [1]),
    range(0, 0),
    split("", ""),
    sort([]),
    distinct([]),
    flat_map(fn(_x) [] end, [1])
  ]
  ok_all(fn(r) r == [] && !nil?(r) end, results)
end

def ok_law_split_keeps_every_field()
  seps = [",", "|", "\n", "ab"]
  words = ["", "a", "x y", "日本", "a,b", "|", "abab"]
  cases = map(
    fn(i)
      [
        nth(i % 4, seps),
        [nth(i % 7, words), nth((i + 2) % 7, words), nth((i + 5) % 7, words)]
      ]
    end,
    range(0, 56)
  )
  ok_all(
    fn(c)
      join(split(join(nth(1, c), nth(0, c)), nth(0, c)), nth(0, c)) ==
        join(nth(1, c), nth(0, c))
    end,
    cases
  ) &&
    split("", ",") == [""] &&
    split("a,b,,", ",") == ["a", "b", "", ""] &&
    size(split(",,", ",")) == 3
end

def ok_law_map_keys_are_exact()
  m = assoc({}, 1, :int)
  get(m, 1) == :int && get(m, 1.0) == nil
end

# ── the ledger ─────────────────────────────────────────────────────────────

def ok_decisions()
  [
    {
      id: "D0001",
      date: "2026-09-27",
      rule: "`==` is value equality: numbers by value (4 == 4.0), strings, lists and maps by content, nil only equals nil.",
      why: "Ruby's answer; maps compared by identity and 4 != 4.0 were silent wrong answers.",
      laws: [
        ["reflexive", ok_law_equal_reflexive],
        ["symmetric", ok_law_equal_symmetric],
        ["numbers by value", ok_law_numbers_by_value],
        ["maps by value", ok_law_maps_by_value]
      ]
    },
    {
      id: "D0002",
      date: "2026-09-27",
      rule: "`!=` is exactly `not(a == b)`.",
      why: "Two operators, one meaning.",
      laws: [["negation", ok_law_not_equal_is_negation]]
    },
    {
      id: "D0003",
      date: "2026-09-27",
      rule: "`contains`, `index_of`, `count_of` and `distinct` use `==`.",
      why: "Membership that disagrees with equality answers the same question two ways.",
      laws: [["membership", ok_law_membership_is_equality]]
    },
    {
      id: "D0004",
      date: "2026-09-27",
      rule: "`nil` and `[]` are different values; `is_empty` is true of both.",
      why: "Ruby: absent is not empty.",
      laws: [["nil is not []", ok_law_nil_is_not_empty_list]]
    },
    {
      id: "D0005",
      date: "2026-09-27",
      rule: "`to_s` gives text: a string is itself, nil is \"\", a float keeps its point (1.0).",
      why: "Ruby's to_s; to_s(1.0) was \"1\".",
      laws: [["literals", ok_law_to_s_literals]]
    },
    {
      id: "D0006",
      date: "2026-09-27",
      rule: "A list or map renders as its blue literal, maps sorted by key: [1, \"a\"], {a: 1}. Interpolation uses to_s.",
      why: "to_s of a map was the word \"map\" and a list lost its brackets.",
      laws: [
        ["collections", ok_law_to_s_collections],
        ["equal maps render equally", ok_law_to_s_equal_maps_render_equally]
      ]
    },
    {
      id: "D0007",
      date: "2026-09-27",
      rule: "`concat` joins the text of one or more arguments, left to right.",
      why: "Ruby's String#concat takes many; two-only was an arity error.",
      laws: [["any arity", ok_law_concat_any_arity]]
    },
    {
      id: "D0008",
      date: "2026-09-27",
      rule: "`/` is float division (7 / 2 == 3.5). Deviation from Ruby, kept.",
      why: "Integer truncation by the division operator is a classic silent bug.",
      laws: [["float division", ok_law_division_is_float]]
    },
    {
      id: "D0009",
      date: "2026-09-27",
      rule: "Map keys are exact: 1 and 1.0 are different keys.",
      why: "Ruby hashes key on eql?, where 1 and 1.0 differ.",
      laws: [["exact keys", ok_law_map_keys_are_exact]]
    },
    {
      id: "D0010",
      date: "2026-09-27",
      rule: "Every value has exactly one kind, each with one predicate: nil?, bool?, integer?, float?, string?, keyword?, list?, map?.",
      why: "float?, map? and bool? did not exist; nil? and list? each also held of the other kind.",
      laws: [["one kind each", ok_law_one_kind_each]]
    },
    {
      id: "D0011",
      date: "2026-09-27",
      rule: "The empty list is always []: no list operation returns nil for an empty result.",
      why: "rest, cdr and append returned nil (Scheme), so rest([1]) == [] was false.",
      laws: [["empty is []", ok_law_empty_list_is_brackets]]
    },
    {
      id: "D0012",
      date: "2026-09-27",
      rule: "`split` keeps every field: n separators give n + 1 fields, and join undoes split. Deviation from Ruby.",
      why: "Ruby drops trailing empty fields; tried, it broke nisshi, kueri and moji: a parser that loses a field loses data.",
      laws: [["join undoes split", ok_law_split_keeps_every_field]]
    }
  ]
end

# A law holds when it returns true. One that throws does not hold: it is
# reported by its decision like any other failure, never aborting the check.
def ok_holds(law)
  try(apply(law, []) == true, catch(_e(), false))
end

# Every law that does not hold, as "id: law", and every decision with no law.
def ok_failures()
  flat_map(fn(d) ok_decision_failures(d) end, ok_decisions())
end

def ok_decision_failures(d)
  laws = get(d, :laws)
  if is_empty(laws)
    ["#{get(d, :id)}: has no law"]
  else
    map(
      fn(l) "#{get(d, :id)}: #{nth(0, l)}" end,
      filter(fn(l) !ok_holds(nth(1, l)) end, laws)
    )
  end
end

# ── the card ───────────────────────────────────────────────────────────────
#
# RULES.md, the whole of what a person or a model must learn to write blue
# beyond Ruby, rendered from the ledger (rules.b writes it; the root Bluefile
# declares it generated, so a stale card is a red build).

def ok_card_line(d)
  "- **#{get(d, :id)}** #{get(d, :rule)}\n"
end

def ok_card()
  head = "# Blue's rules\n\nGenerated from `bidamas/okite/okite.b` by `rules.b`: do not edit.\nEvery rule is enforced by laws in okite; a rule without a passing law fails\nthe build.\n\n**Blue values behave like Ruby's, except where a rule below says otherwise.**\n\n"
  concat(head, join(map(fn(d) ok_card_line(d) end, ok_decisions()), ""))
end

# ── tests ──────────────────────────────────────────────────────────────────

test "every decision is enforced, and every law holds"
  assert ok_failures() == []
end

test "decision ids are unique and in order"
  ids = map(fn(d) get(d, :id) end, ok_decisions())
  assert ids == distinct(ids)
  assert ids == sort(ids)
end

test "the card stays small: a rule is a line, and the card fits in 40"
  card = ok_card()
  assert size(lines(card)) <= 40
  assert ok_all(fn(d) length(get(d, :rule)) <= 160 end, ok_decisions())
end

test "the generator covers every kind (anti-vacuity)"
  vs = ok_values(99, 300)
  assert some(fn(v) integer?(v) end, vs)
  assert some(fn(v) float?(v) end, vs)
  assert some(fn(v) string?(v) end, vs)
  assert some(fn(v) v == nil end, vs)
  assert some(fn(v) list?(v) && !is_empty(v) end, vs)
  assert some(fn(v) map?(v) end, vs)
end
