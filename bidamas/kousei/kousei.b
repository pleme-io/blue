use("kyohi", [:refusal, :standing])
use("retsu", [:contains, :flat_map, :index_of, :is_empty, :size])

# kousei (構成) — a system composed entry by entry: each entry checked, configured off, tuned or refused alone, then judged into what stands.
#
# A declaration is a list of entries. A schema maps each kind to a field
# table. `judge` refuses each bad entry on its own and lets its valid siblings
# stand, so one typo never takes a whole declaration down.

# nil when ok, else why.
def verdict(ok, why)
  if ok
    nil
  else
    why
  end
end

def flag()
  (v) -> verdict(boolean?(v), "#{v} is not true or false")
end

def text()
  (v) -> verdict(string?(v) and length(v) > 0, "#{v} is not text")
end

def one_of(choices)
  fn(v)
    verdict(
      contains(choices, v),
      "#{v} is not one of #{join(map(to_s, choices), ", ")}"
    )
  end
end

def int_in(lo, hi)
  fn(v)
    verdict(
      integer?(v) and v >= lo and v <= hi,
      "#{v} is not a whole number in #{lo}..#{hi}"
    )
  end
end

# Every element passes `check`; the first failure is the why.
def list_of(check)
  fn(v)
    if not list?(v)
      "#{v} is not a list"
    else
      first_why(check, v)
    end
  end
end

def first_why(check, xs)
  whys = filter((w) -> w != nil, map((x) -> check(x), xs))
  if is_empty(whys)
    nil
  else
    nth(0, whys)
  end
end

# A field of a record: its key and its check, optional unless `required`.
def field(key, check)
  {key:, check:, required: false}
end

def required(f)
  assoc(f, :required, true)
end

# Why a record breaks its table: missing required fields, bad values, and keys the table does not know.
def record_whys(table, m)
  if not map?(m)
    ["the value is not a record"]
  else
    keys = map((f) -> get(f, :key), table)
    known = map(
      fn(f)
        v = get(m, get(f, :key))
        if v.nil?
          verdict(not get(f, :required), "#{get(f, :key)} is required")
        else
          w = get(f, :check)(v)
          verdict(w.nil?, "#{get(f, :key)}: #{w}")
        end
      end,
      table
    )
    extra = map(
      (p) -> "#{nth(0, p)} is not a field",
      filter((p) -> not contains(keys, nth(0, p)), map_entries(m))
    )
    filter((w) -> w != nil, append(known, extra))
  end
end

# A record table that checks only the fields it is given.
def loosened(table)
  map((f) -> assoc(f, :required, false), table)
end

def entry(kind, name, value)
  {entry: kind, name:, value:}
end

def kind_of(e)
  get(e, :entry)
end

def name_of(e)
  get(e, :name)
end

def value_of(e)
  get(e, :value)
end

# Declared, and configured off: it stays in the declaration and does nothing.
def off(kind, name)
  entry(:off, name, {target: kind})
end

# Fields laid over an entry declared earlier.
def tune(kind, name, fields)
  entry(:tune, name, {target: kind, fields:})
end

def where(e)
  "#{kind_of(e)} #{name_of(e)}"
end

def refuse(fault, e, why)
  refusal(fault, "#{where(e)}: #{why}")
end

def overlay(base, fields)
  reduce(
    (acc, p) -> assoc(acc, nth(0, p), nth(1, p)),
    base,
    map_entries(fields)
  )
end

def targets?(t, e)
  kind_of(e) == get(value_of(t), :target) and name_of(e) == name_of(t)
end

def duplicate_marks(es)
  ids = map((e) -> [kind_of(e), name_of(e)], es)
  map(
    fn(i)
      if index_of(ids, nth(i, ids)) < i
        [refuse(:duplicate, nth(i, es), "declared twice; the first stands")]
      else
        []
      end
    end,
    range(0, size(es))
  )
end

def entry_marks(schema, es)
  map(
    fn(e)
      table = get(schema, kind_of(e))
      if table.nil?
        [refuse(:unknown_kind, e, "no such kind")]
      else
        map((w) -> refuse(:invalid, e, w), record_whys(table, value_of(e)))
      end
    end,
    es
  )
end

def tune_marks(schema, t, es)
  table = get(schema, get(value_of(t), :target))
  if not any?((e) -> targets?(t, e), es)
    [refuse(:unknown_entry, t, "nothing declared to tune")]
  else
    map(
      (w) -> refuse(:invalid, t, w),
      record_whys(loosened(table), get(value_of(t), :fields))
    )
  end
end

def tuned(e, tunes)
  reduce(
    fn(acc, t)
      if targets?(t, acc)
        entry(
          kind_of(acc),
          name_of(acc),
          overlay(value_of(acc), get(value_of(t), :fields))
        )
      else
        acc
      end
    end,
    e,
    tunes
  )
end

def zipped(xs, ys)
  map((i) -> append(nth(i, xs), nth(i, ys)), range(0, size(xs)))
end

# The declaration judged against `schema`: `accepted` (tuned, not off), `off`, and `refusals`, each refusal scoped to its entry.
def judge(schema, entries)
  shaped = filter((e) -> map?(e) and kind_of(e) != nil, entries)
  malformed = map(
    (e) -> refusal(:invalid, "#{e} is not an entry"),
    filter((e) -> not (map?(e) and kind_of(e) != nil), entries)
  )
  offs = filter((e) -> kind_of(e) == :off, shaped)
  tunes = filter((e) -> kind_of(e) == :tune, shaped)
  plain = filter((e) -> kind_of(e) != :off and kind_of(e) != :tune, shaped)
  marks = zipped(duplicate_marks(plain), entry_marks(schema, plain))
  base = standing(plain, marks)
  tune_bad = map((t) -> tune_marks(schema, t, base), tunes)
  good_tunes = standing(tunes, tune_bad)
  retuned = map((e) -> tuned(e, good_tunes), base)
  after = map(
    fn(e)
      map(
        (w) -> refuse(:invalid, e, w),
        record_whys(get(schema, kind_of(e)), value_of(e))
      )
    end,
    retuned
  )
  sound = standing(retuned, after)
  off_bad = map(
    fn(o)
      if any?((e) -> targets?(o, e), sound)
        []
      else
        [refuse(:unknown_entry, o, "nothing declared to configure off")]
      end
    end,
    offs
  )
  good_offs = standing(offs, off_bad)
  is_off = (e) -> any?((o) -> targets?(o, e), good_offs)
  {
    accepted: filter((e) -> not is_off(e), sound),
    off: filter(is_off, sound),
    refusals: append(
      malformed,
      flat_map(marks, (r) -> r),
      flat_map(tune_bad, (r) -> r),
      flat_map(after, (r) -> r),
      flat_map(off_bad, (r) -> r)
    )
  }
end

# The accepted entries of one kind.
def of_kind(judged, kind)
  filter((e) -> kind_of(e) == kind, get(judged, :accepted))
end

def schema_fixture()
  {
    plane: [
      required(field(:listen, text)),
      field(:surfaces, list_of(one_of([:ingest, :ui])))
    ],
    rule: [field(:enabled, flag)]
  }
end

def fixture()
  [
    entry(:plane, "external", {listen: "127.0.0.1:8443", surfaces: [:ingest]}),
    entry(:plane, "internal", {listen: "127.0.0.1:8444", surfaces: [:ui]}),
    entry(:rule, "segregation", {enabled: true})
  ]
end

def faults(j)
  map((r) -> nth(0, r), get(j, :refusals))
end

test "a clean declaration stands whole"
  j = judge(schema_fixture, fixture)
  assert size(get(j, :accepted)) == 3
  assert get(j, :refusals) == []
  assert get(j, :off) == []
end

test "a bad entry is refused alone and its siblings stand"
  j = judge(
    schema_fixture,
    append(
      fixture,
      [
        entry(:plane, "broken", {surfaces: [:nope]}),
        entry(:widget, "x", {}),
        entry(:rule, "segregation", {enabled: false}),
        42
      ]
    )
  )
  assert size(get(j, :accepted)) == 3
  assert faults(j) == [:invalid, :invalid, :invalid, :unknown_kind, :duplicate]
  assert value_of(nth(2, get(j, :accepted))) == {enabled: true}
end

test "off keeps the entry declared and out of what is accepted"
  j = judge(schema_fixture, append(fixture, [off(:plane, "internal")]))
  assert map(name_of, get(j, :accepted)) == ["external", "segregation"]
  assert map(name_of, get(j, :off)) == ["internal"]
  j2 = judge(schema_fixture, append(fixture, [off(:plane, "nowhere")]))
  assert faults(j2) == [:unknown_entry]
  assert size(get(j2, :accepted)) == 3
end

test "a tune lays fields over its entry, and a bad tune is refused alone"
  j = judge(
    schema_fixture,
    append(
      fixture,
      [
        tune(:plane, "external", {surfaces: [:ingest, :ui]}),
        tune(:plane, "external", {listen: 7}),
        tune(:plane, "ghost", {listen: "x"})
      ]
    )
  )
  assert get(value_of(nth(0, of_kind(j, :plane))), :surfaces) == [:ingest, :ui]
  assert get(value_of(nth(0, of_kind(j, :plane))), :listen) == "127.0.0.1:8443"
  assert faults(j) == [:invalid, :unknown_entry]
end

test "unknown fields and missing required fields are reasons, not crashes"
  assert record_whys(get(schema_fixture, :plane), {surfaces: []}) ==
    ["listen is required"]
  assert record_whys(get(schema_fixture, :plane), {listen: "a", port: 1}) ==
    ["port is not a field"]
  assert record_whys(get(schema_fixture, :plane), "x") ==
    ["the value is not a record"]
end
