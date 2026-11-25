@moduledoc """
hadome (歯止め) — a baseline ratchet: recorded debt may shrink or hold, never grow.

One ledger for every one-way gate, the blue rung of joeira-ratchet: rows are
`kind: key N`, and a gate judges its measures with failures. A measure that
could not be taken is blind, and blind is red. A ledger is written only by
record: every fall is banked (tighten, joeira-ratchet's bank), a row no longer
measured leaves, and a rise or a new row needs a typed receipt,
`<kind>: <why>` with a kind of receipt_kinds, kept in the file as a
`# receipt:` line beside every earlier one.

    render("rust", []) #=> ""
"""

use("kyohi", %i[kinds ok refusal refusal_of refused value why])

use(
  "moji",
  %i[after_first after_last before_first before_last includes lines trim]
)

use("retsu", %i[flat_map is_empty last])

def row(kind, key, size)
  {kind:, key:, size:}
end

def measurement(key, size)
  {key:, size:}
end

@doc """
blind: a measured row whose measure could not be taken, and why. failures names it red and record refuses it; it is never read as zero.

    blind("purity-bytes", "crates/a", "unreadable")[:blind] #=> "unreadable"
"""
def blind(kind, key, why)
  {kind:, key:, blind: why}
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
  judge_within(rows, kind, key, measured, 0)
end

@doc """
judge_within: judge, holding a measure up to permille thousandths past its row.

    judge_within([row("cost", "fib", 1000)], "cost", "fib", 1010, 10) #=> {verdict: :held}
"""
def judge_within(rows, kind, key, measured, permille)
  r = recorded(rows, kind, key)
  if r.nil?
    {verdict: :unrecorded}
  elsif measured * 1000 > r * (1000 + permille)
    {verdict: :grew, recorded: r, grew: measured - r}
  else
    {verdict: :held}
  end
end

def failure(rows, kind, m, permille)
  key = m[:key]
  size = m[:size]
  if m[:blind] != nil
    refusal(:blind, "#{kind}: #{key} is blind: #{m[:blind]}")
  else
    j = judge_within(rows, kind, key, size, permille)
    v = j[:verdict]
    beyond = if permille == 0
      ""
    else
      ", beyond its #{to_s(permille)} per mille tolerance"
    end
    if v == :unrecorded
      refusal(
        :unrecorded,
        "#{kind}: #{key} measures #{to_s(size)} and the baseline has no row for it"
      )
    elsif v == :grew
      refusal(
        :grew,
        "#{kind}: #{key} measures #{to_s(size)}, past its recorded #{to_s(j[:recorded])} by #{to_s(j[:grew])}#{beyond}"
      )
    end
  end
end

@doc """
failures: every key that grew, is new, or is blind.

    failures(example_baseline, "entry", []) #=> []
"""
def failures(rows, kind, measurements)
  failures_within(rows, kind, measurements, 0)
end

@doc """
failures_within: every key that is new or grew past its row by more than permille thousandths.

    failures_within([row("cost", "fib", 1000)], "cost", [measurement("fib", 1010)], 10) #=> []
"""
def failures_within(rows, kind, measurements, permille)
  filter(
    (f) -> f != nil,
    map((m) -> failure(rows, kind, m, permille), measurements)
  )
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

@doc """
receipted: a baseline's text, keeping the old text's comment lines, then the receipt line, then rows.

    receipted("", nil, "") #=> ""
"""
def receipted(old, receipt, rows)
  notes = append(
    filter((l) -> starts_with?(l, "#"), lines(old)),
    if receipt.nil?
      []
    else
      ["# receipt: #{receipt}"]
    end
  )
  if is_empty(notes)
    rows
  else
    "#{unlines(notes)}#{rows}"
  end
end

@doc """
tighten: the rows of `kind` a record banks, as joeira-ratchet's bank does: each measured key at its recorded size or lower, never raised. A key no longer measured, or never recorded, is left out; a blind measure keeps its row.

    tighten([row("cost", "fib", 9), row("cost", "gone", 4)], "cost", [measurement("fib", 7)]) #=> [row("cost", "fib", 7)]
"""
def tighten(rows, kind, measurements)
  flat_map(
    sort_keyed((m) -> m[:key], measurements),
    fn(m)
      was = recorded(rows, kind, m[:key])
      if was.nil?
        []
      elsif m[:blind] != nil or was < m[:size]
        [row(kind, m[:key], was)]
      else
        [row(kind, m[:key], m[:size])]
      end
    end
  )
end

@doc """
receipt_kinds: the kinds of reason a raised or new row carries, written `"<kind>: <why>"`: a row's first measure (`first-measure`), the measure itself changed (`measurement`), a fix costs work (`correctness`), new behaviour costs work (`capability`), the toolchain or host changed (`platform`), or a gain given back on purpose, naming what it gives back (`un-gain`, the ratchet law's word).

    receipt_kinds #=> ["first-measure", "measurement", "correctness", "capability", "platform", "un-gain"]
"""
def receipt_kinds()
  %w[first-measure measurement correctness capability platform un-gain]
end

@doc """
receipt_refusal: why a receipt is not a typed reason, or nil when it is one: a kind from receipt_kinds, a colon and a reason. No receipt is no refusal.

    receipt_refusal(nil) #=> nil
    receipt_refusal("correctness: the overflow check") #=> nil
    kinds([receipt_refusal("faster later")]) #=> [:receipt]
"""
def receipt_refusal(receipt)
  if receipt != nil
    named = trim(before_first(receipt, ":"))
    reason = if includes(receipt, ":")
      trim(after_first(receipt, ":"))
    else
      ""
    end
    if not member?(named, receipt_kinds) or reason == ""
      refusal(
        :receipt,
        "a receipt is \"<kind>: <why>\" with a kind of #{join(receipt_kinds, ", ")}; got \"#{receipt}\""
      )
    end
  end
end

@doc """
record: write the ledger at `path` from the measured rows, of one kind or more, and answer a kyohi result: ok of the count of rows written, or the refusal that wrote nothing. Every fall is banked and a key no longer measured leaves (tighten). A row that rises or is new needs `opts.receipt`, checked by receipt_refusal and kept as a `# receipt:` line beside the file's earlier ones. A blind measure is refused.

    kinds([refusal_of(record("/nonexistent/hadome", [blind("k", "a", "unread")], {}))]) #=> [:blind]
"""
def record(path, measured, opts)
  old = if is_file?(path)
    read_file(path)
  else
    ""
  end
  rows = parse(old)
  receipt = opts[:receipt]
  of_kind = (xs, k) -> filter((m) -> m[:kind] == k, xs)
  ks = distinct(sort_keyed((k) -> k, map((m) -> m[:kind], measured)))
  found = flat_map(ks, (k) -> failures(rows, k, of_kind(measured, k)))
  blinds = filter((f) -> kyohi::kind(f) == :blind, found)
  rises = filter((f) -> kyohi::kind(f) != :blind, found)
  bad = receipt_refusal(receipt)
  if blinds != []
    refused(refusal(:blind, join_lines(map(why, blinds))))
  elsif bad != nil
    refused(bad)
  elsif rises != [] and receipt.nil?
    refused(
      refusal(
        :unreceipted,
        join_lines(
          append(
            map(why, rises),
            [
              "a raised or new row needs a receipt, \"<kind>: <why>\" with a kind of #{join(receipt_kinds, ", ")}"
            ]
          )
        )
      )
    )
  else
    kept = if receipt.nil?
      flat_map(ks, (k) -> tighten(rows, k, of_kind(measured, k)))
    else
      measured
    end
    write_file(
      path,
      receipted(
        old,
        receipt,
        join(map((k) -> render(k, of_kind(kept, k)), ks), "")
      )
    )
    ok(length(kept))
  end
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
  assert kinds(failures(example_baseline, "entry", ms)) == %i[grew unrecorded]
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

test "a measure within its tolerance holds, and one past it grew"
  rows = [row("cost", "fib", 1000)]
  assert judge_within(rows, "cost", "fib", 1010, 10) == {verdict: :held}
  assert judge_within(rows, "cost", "fib", 1011, 10) ==
    {verdict: :grew, recorded: 1000, grew: 11}
  assert judge_within(rows, "cost", "fib", 1001, 0) ==
    {verdict: :grew, recorded: 1000, grew: 1}
  assert judge_within(rows, "cost", "nope", 1, 10) == {verdict: :unrecorded}
end

test "failures_within names a grown row with its tolerance and skips a held one"
  rows = [row("cost", "fib", 1000), row("cost", "hello", 10)]
  ms = [measurement("fib", 1200), measurement("hello", 10)]
  got = failures_within(rows, "cost", ms, 10)
  assert kinds(got) == [:grew]
  assert includes(got[0][1], "past its recorded 1000 by 200")
  assert includes(got[0][1], "10 per mille")
  assert failures_within(rows, "cost", [measurement("fib", 1005)], 10) == []
end

test "tighten banks as joeira-ratchet's bank does: a fall lowers its row, a rise never raises one, and an orphan or a new key leaves"
  push = "wf/image-push.yml::push/Build and push"
  tendril = "docs/CLAUDE.md::The Tendril Method"
  assert tighten(
    example_baseline,
    "entry",
    [measurement(push, 12), measurement(tendril, 4139)]
  ) == [row("entry", tendril, 4139), row("entry", push, 12)]
  assert tighten(
    example_baseline,
    "entry",
    [measurement(push, 61), measurement(tendril, 9000)]
  ) == [row("entry", tendril, 4139), row("entry", push, 60)]
  assert tighten(example_baseline, "entry", [measurement(tendril, 4000)]) ==
    [row("entry", tendril, 4000)]
  assert tighten(example_baseline, "entry", [measurement("new", 7)]) == []
  assert tighten(example_baseline, "host", [measurement(push, 1)]) == []
end

test "tighten is a fixed point once banked, and a blind measure keeps its row"
  ms = [measurement("a", 3), measurement("b", 8)]
  once = tighten([row("k", "a", 5), row("k", "b", 8)], "k", ms)
  assert tighten(once, "k", ms) == once
  assert failures(once, "k", ms) == []
  assert tighten(once, "k", [blind("k", "a", "unread")]) == [row("k", "a", 3)]
end

test "a blind measure is red, never read as zero"
  got = failures(
    [row("k", "a", 5)],
    "k",
    [blind("k", "a", "blue ast exited 1"), measurement("b", 0)]
  )
  assert kinds(got) == %i[blind unrecorded]
  assert includes(got[0][1], "k: a is blind: blue ast exited 1")
end

test "a receipt is a kind of receipt_kinds, a colon and a reason"
  assert receipt_kinds ==
    %w[first-measure measurement correctness capability platform un-gain]
  assert receipt_refusal(nil).nil?
  assert receipt_refusal("un-gain: mutual's rows leave the gate").nil?
  assert receipt_refusal("first-measure: linux").nil?
  assert kinds([receipt_refusal("first linux measure")]) == [:receipt]
  assert kinds([receipt_refusal("measurement:")]) == [:receipt]
  assert kinds([receipt_refusal("faster: later")]) == [:receipt]
end

@doc """
ledger_at: a scratch ledger file holding `text`, for a test of record.

    read_file(ledger_at("doc.baseline", "k: a 1")) #=> "k: a 1"
"""
def ledger_at(name, text)
  path = path_join(temp_dir("hadome"), name)
  write_file(path, text)
  path
end

test "a record banks a fall and drops a gone row with no receipt, keeping every receipt line"
  path = ledger_at(
    "fall.baseline",
    unlines(["# receipt: measurement: first", "k: a 5", "k: gone 2"])
  )
  got = record(path, [row("k", "a", 3)], {})
  assert value(got) == 1
  assert read_file(path) == unlines(["# receipt: measurement: first", "k: a 3"])
end

test "a rise or a new row with no receipt is refused and the ledger is untouched"
  text = unlines(["k: a 5"])
  path = ledger_at("rise.baseline", text)
  up = record(path, [row("k", "a", 6)], {})
  assert kinds([refusal_of(up)]) == [:unreceipted]
  assert includes(
    refusal_of(up)[1],
    "k: a measures 6, past its recorded 5 by 1"
  )
  assert kinds([refusal_of(record(path, [row("k", "b", 1)], {}))]) ==
    [:unreceipted]
  assert read_file(path) == text
end

test "a receipted rise is written with its receipt, and a malformed receipt is refused"
  path = ledger_at("raise.baseline", unlines(["k: a 5"]))
  assert kinds(
    [refusal_of(record(path, [row("k", "a", 6)], {receipt: "bigger"}))]
  ) == [:receipt]
  got = record(
    path,
    [row("k", "a", 6), row("j", "b", 1)],
    {receipt: "capability: the b row"}
  )
  assert value(got) == 2
  assert read_file(path) ==
    unlines(["# receipt: capability: the b row", "j: b 1", "k: a 6"])
end

test "a blind measure is refused by a record, even with a receipt, and nothing is written"
  text = unlines(["k: a 5"])
  path = ledger_at("blind.baseline", text)
  got = record(
    path,
    [blind("k", "a", "unreadable"), row("k", "b", 1)],
    {receipt: "measurement: b"}
  )
  assert kinds([refusal_of(got)]) == [:blind]
  assert read_file(path) == text
  assert value(record(ledger_at("none.baseline", ""), [], {})) == 0
end

test "receipted keeps every comment, adds the receipt, and drops old rows"
  old = unlines(["# receipt: first", "cost: fib 1"])
  assert receipted(old, "raised", unlines(["cost: fib 2"])) ==
    unlines(["# receipt: first", "# receipt: raised", "cost: fib 2"])
  assert receipted(old, nil, unlines(["cost: fib 2"])) ==
    unlines(["# receipt: first", "cost: fib 2"])
  assert receipted("", nil, "") == ""
end
