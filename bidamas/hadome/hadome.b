use("kyohi", [:kinds, :refusal])

use(
  "moji",
  [:after_first, :after_last, :before_first, :before_last, :includes, :lines]
)

use("retsu", [:is_empty, :last])

# hadome (歯止め) — a baseline ratchet: recorded debt may shrink or hold, never grow.

def row(kind, key, size)
  {kind: kind, key: key, size: size}
end

def measurement(key, size)
  {key: key, size: size}
end

def sized(kind, rest)
  r = replace(rest, "\t", " ")
  if includes(r, " ")
    n = to_int(trim(after_last(r, " ")))
    if n == nil || n < 0
      nil
    else
      row(kind, trim(before_last(r, " ")), n)
    end
  else
    nil
  end
end

def parse_line(line)
  t = trim(line)
  if t == "" || starts_with?(t, "#") || !includes(t, ":")
    nil
  else
    sized(trim(before_first(t, ":")), trim(after_first(t, ":")))
  end
end

def parse(text)
  filter(fn(r) r != nil end, map(fn(l) parse_line(l) end, lines(text)))
end

def recorded(rows, kind, key)
  hit = filter(fn(r) get(r, :kind) == kind && get(r, :key) == key end, rows)
  if is_empty(hit)
    nil
  else
    get(last(hit), :size)
  end
end

def judge(rows, kind, key, measured)
  r = recorded(rows, kind, key)
  if r == nil
    {verdict: :unrecorded}
  elsif measured > r
    {verdict: :grew, recorded: r, grew: measured - r}
  else
    {verdict: :held}
  end
end

def failure(rows, kind, m)
  key = get(m, :key)
  size = get(m, :size)
  j = judge(rows, kind, key, size)
  v = get(j, :verdict)
  if v == :unrecorded
    refusal(
      :unrecorded,
      "#{kind}: #{key} measures #{to_s(size)} and the baseline has no row for it"
    )
  elsif v == :grew
    refusal(
      :grew,
      "#{kind}: #{key} measures #{to_s(size)}, past its recorded #{to_s(get(j, :recorded))} by #{to_s(get(j, :grew))}"
    )
  else
    nil
  end
end

def failures(rows, kind, measurements)
  filter(
    fn(f) f != nil end,
    map(fn(m) failure(rows, kind, m) end, measurements)
  )
end

def keys_of(rows, kind)
  ks = map(
    fn(r) get(r, :key) end,
    filter(fn(r) get(r, :kind) == kind end, rows)
  )
  distinct(sort_keyed(fn(k) k end, ks))
end

def orphans(rows, kind, live)
  filter(fn(k) !member?(k, live) end, keys_of(rows, kind))
end

def shrunk(rows, kind, measurements)
  filter(
    fn(m)
      recorded(rows, kind, get(m, :key)) != nil &&
        get(m, :size) < recorded(rows, kind, get(m, :key))
    end,
    measurements
  )
end

def render(kind, measurements)
  sorted = sort_keyed(fn(m) get(m, :key) end, measurements)
  join(
    map(fn(m) "#{kind}: #{get(m, :key)} #{to_s(get(m, :size))}\n" end, sorted),
    ""
  )
end

def example_baseline()
  [
    row("entry", "docs/CLAUDE.md::The Tendril Method", 4139),
    row("entry", "wf/image-push.yml::push/Build and push", 60)
  ]
end

test "an unrecorded key is a new violation"
  assert judge(example_baseline(), "entry", "nope", 1) == {verdict: :unrecorded}
  assert judge([], "entry", "anything", 0) == {verdict: :unrecorded}
end

test "recorded debt may hold or shrink"
  assert judge(
    example_baseline(),
    "entry",
    "wf/image-push.yml::push/Build and push",
    60
  ) ==
    {verdict: :held}
  assert judge(
    example_baseline(),
    "entry",
    "wf/image-push.yml::push/Build and push",
    12
  ) ==
    {verdict: :held}
end

test "recorded debt that grows by one fails"
  assert judge(
    example_baseline(),
    "entry",
    "wf/image-push.yml::push/Build and push",
    61
  ) ==
    {verdict: :grew, recorded: 60, grew: 1}
end

test "a row covers only its own kind"
  assert judge(
    example_baseline(),
    "host",
    "wf/image-push.yml::push/Build and push",
    1
  ) ==
    {verdict: :unrecorded}
end

test "parse keeps keys containing spaces"
  rows = parse("entry: docs/CLAUDE.md::The Tendril Method 4139\n")
  assert rows == [row("entry", "docs/CLAUDE.md::The Tendril Method", 4139)]
end

test "a malformed line covers nothing rather than weakening the gate"
  assert parse(
    "# a comment\n\nentry: no-size-here\nnocolon 12\nentry: bad-size xyz\nentry: negative -3\n"
  ) ==
    []
end

test "a later row for the same key wins, as a map insert does"
  assert recorded(parse("entry: k 5\nentry: k 9\n"), "entry", "k") == 9
end

test "a row whose subject is gone is an orphan"
  assert orphans(
    example_baseline(),
    "entry",
    ["docs/CLAUDE.md::The Tendril Method"]
  ) ==
    ["wf/image-push.yml::push/Build and push"]
  assert orphans(
    example_baseline(),
    "entry",
    [
      "docs/CLAUDE.md::The Tendril Method",
      "wf/image-push.yml::push/Build and push"
    ]
  ) ==
    []
end

test "orphans does not simply return everything"
  assert orphans(example_baseline(), "entry", []) ==
    [
      "docs/CLAUDE.md::The Tendril Method",
      "wf/image-push.yml::push/Build and push"
    ]
  assert orphans([], "entry", []) == []
end

test "failures name every unrecorded and grown measurement, and nothing held"
  ms = [
    measurement("wf/image-push.yml::push/Build and push", 61),
    measurement("nope", 3),
    measurement("docs/CLAUDE.md::The Tendril Method", 4139)
  ]
  assert kinds(failures(example_baseline(), "entry", ms)) ==
    [:grew, :unrecorded]
  assert failures(example_baseline(), "entry", []) == []
end

test "shrunk lists only measurements below their row"
  ms = [
    measurement("wf/image-push.yml::push/Build and push", 12),
    measurement("docs/CLAUDE.md::The Tendril Method", 4139),
    measurement("nope", 1)
  ]
  assert shrunk(example_baseline(), "entry", ms) ==
    [measurement("wf/image-push.yml::push/Build and push", 12)]
end

test "render is sorted, so a baseline diffs stably, and parses back"
  a = render("rust", [measurement("zebra", 1), measurement("alpha", 2)])
  b = render("rust", [measurement("alpha", 2), measurement("zebra", 1)])
  assert a == "rust: alpha 2\nrust: zebra 1\n"
  assert a == b
  assert parse(a) == [row("rust", "alpha", 2), row("rust", "zebra", 1)]
  assert render("rust", []) == ""
end
