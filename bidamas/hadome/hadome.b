@moduledoc """
hadome (歯止め) — a baseline ratchet: recorded debt may shrink or hold, never grow.

    render("rust", []) #=> ""
"""

use("kyohi", [:kinds, :refusal])

use(
  "moji",
  [
    :after_first,
    :after_last,
    :before_first,
    :before_last,
    :includes,
    :lines,
    :trim
  ]
)

use("retsu", [:is_empty, :last])

def row(kind, key, size)
  {kind:, key:, size:}
end

def measurement(key, size)
  {key:, size:}
end

def sized(kind, rest)
  r = replace(rest, "\t", " ")
  if includes(r, " ")
    n = to_int(trim(after_last(r, " ")))
    if n.nil? or n < 0
      nil
    else
      row(kind, trim(before_last(r, " ")), n)
    end
  end
end

def parse_line(line)
  t = trim(line)
  if t == "" or starts_with?(t, "#") or not includes(t, ":")
    nil
  else
    sized(trim(before_first(t, ":")), trim(after_first(t, ":")))
  end
end

@doc """
parse: a baseline file to rows.

    parse("# a comment\n\nentry: no-size-here\nnocolon 12\nentry: bad-size xyz\nentry: negative -3\n") #=> []
"""
def parse(text)
  filter((r) -> r != nil, map(parse_line, lines(text)))
end

def recorded(rows, kind, key)
  hit = filter((r) -> r[:kind] == kind and r[:key] == key, rows)
  if is_empty(hit)
    nil
  else
    last(hit)[:size]
  end
end

@doc """
judge: whether a measure grew past its recorded size.

    judge([], "entry", "anything", 0) #=> {verdict: :unrecorded}
"""
def judge(rows, kind, key, measured)
  r = recorded(rows, kind, key)
  if r.nil?
    {verdict: :unrecorded}
  elsif measured > r
    {verdict: :grew, recorded: r, grew: measured - r}
  else
    {verdict: :held}
  end
end

def failure(rows, kind, m)
  key = m[:key]
  size = m[:size]
  j = judge(rows, kind, key, size)
  v = j[:verdict]
  if v == :unrecorded
    refusal(
      :unrecorded,
      "#{kind}: #{key} measures #{to_s(size)} and the baseline has no row for it"
    )
  elsif v == :grew
    refusal(
      :grew,
      "#{kind}: #{key} measures #{to_s(size)}, past its recorded #{to_s(j[:recorded])} by #{to_s(j[:grew])}"
    )
  end
end

@doc """
failures: every key that grew or is new.

    failures(example_baseline, "entry", []) #=> []
"""
def failures(rows, kind, measurements)
  filter((f) -> f != nil, map((m) -> failure(rows, kind, m), measurements))
end

def keys_of(rows, kind)
  ks = map((r) -> r[:key], filter((r) -> r[:kind] == kind, rows))
  distinct(sort_keyed((k) -> k, ks))
end

@doc """
orphans: recorded keys that no longer exist.

    orphans([], "entry", []) #=> []
"""
def orphans(rows, kind, live)
  filter((k) -> not member?(k, live), keys_of(rows, kind))
end

@doc """
shrunk: keys that fell below their record and can be tightened.
"""
def shrunk(rows, kind, measurements)
  filter(
    fn(m)
      recorded(rows, kind, m[:key]) != nil and
        m[:size] < recorded(rows, kind, m[:key])
    end,
    measurements
  )
end

@doc """
render: measurements as a baseline file, stable order.

    render("rust", []) #=> ""
"""
def render(kind, measurements)
  sorted = sort_keyed((m) -> m[:key], measurements)
  join(
    map((m) -> unlines(["#{kind}: #{m[:key]} #{to_s(m[:size])}"]), sorted),
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
  assert judge(example_baseline, "entry", "nope", 1) == {verdict: :unrecorded}
  assert judge([], "entry", "anything", 0) == {verdict: :unrecorded}
end

test "recorded debt may hold or shrink"
  assert judge(
    example_baseline,
    "entry",
    "wf/image-push.yml::push/Build and push",
    60
  ) == {verdict: :held}
  assert judge(
    example_baseline,
    "entry",
    "wf/image-push.yml::push/Build and push",
    12
  ) == {verdict: :held}
end

test "recorded debt that grows by one fails"
  assert judge(
    example_baseline,
    "entry",
    "wf/image-push.yml::push/Build and push",
    61
  ) == {verdict: :grew, recorded: 60, grew: 1}
end

test "a row covers only its own kind"
  assert judge(
    example_baseline,
    "host",
    "wf/image-push.yml::push/Build and push",
    1
  ) == {verdict: :unrecorded}
end

test "parse keeps keys containing spaces"
  rows = parse(unlines(["entry: docs/CLAUDE.md::The Tendril Method 4139"]))
  assert rows == [row("entry", "docs/CLAUDE.md::The Tendril Method", 4139)]
end

test "a malformed line covers nothing rather than weakening the gate"
  assert parse(
    unlines(
      [
        "# a comment",
        "",
        "entry: no-size-here",
        "nocolon 12",
        "entry: bad-size xyz",
        "entry: negative -3"
      ]
    )
  ) == []
end

test "a later row for the same key wins, as a map insert does"
  assert recorded(parse(unlines(["entry: k 5", "entry: k 9"])), "entry", "k") ==
    9
end

test "a row whose subject is gone is an orphan"
  assert orphans(
    example_baseline,
    "entry",
    ["docs/CLAUDE.md::The Tendril Method"]
  ) == ["wf/image-push.yml::push/Build and push"]
  assert orphans(
    example_baseline,
    "entry",
    [
      "docs/CLAUDE.md::The Tendril Method",
      "wf/image-push.yml::push/Build and push"
    ]
  ) == []
end

test "orphans does not simply return everything"
  assert orphans(example_baseline, "entry", []) ==
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
  assert kinds(failures(example_baseline, "entry", ms)) == [:grew, :unrecorded]
  assert failures(example_baseline, "entry", []) == []
end

test "shrunk lists only measurements below their row"
  ms = [
    measurement("wf/image-push.yml::push/Build and push", 12),
    measurement("docs/CLAUDE.md::The Tendril Method", 4139),
    measurement("nope", 1)
  ]
  assert shrunk(example_baseline, "entry", ms) ==
    [measurement("wf/image-push.yml::push/Build and push", 12)]
end

test "render is sorted, so a baseline diffs stably, and parses back"
  a = render("rust", [measurement("zebra", 1), measurement("alpha", 2)])
  b = render("rust", [measurement("alpha", 2), measurement("zebra", 1)])
  assert a == unlines(["rust: alpha 2", "rust: zebra 1"])
  assert a == b
  assert parse(a) == [row("rust", "alpha", 2), row("rust", "zebra", 1)]
  assert render("rust", []) == ""
end
