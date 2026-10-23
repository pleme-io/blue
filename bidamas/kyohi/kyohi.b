use("retsu", [:find_first, :first, :flat_map, :is_empty, :size])

# kyohi (拒否) — refusals, as data.
#
# A refusal is `[kind, why]`: a keyword naming what was refused and the reason,
# usually text. A check that can fail several ways at once returns EVERY
# refusal it finds, as a list, instead of throwing on the first, so a caller
# sees the whole picture and can test for one kind. `refuse` turns that list
# into one thrown error when the caller wants to stop.
#
# kueri, kinji and nisshi each wrote this vocabulary, and kueri's `refuse` and
# kinji's were the same definition. It lives here once; their names are
# bridges to these (`legacy_names`) until each package's 0.2.0.

# A refusal of `kind`, because `why`.
def refusal(kind, why)
  [kind, why]
end

# What was refused: the refusal's keyword.
def kind(r)
  first(r)
end

# Why it was refused.
def why(r)
  nth(1, r)
end

# The kind of each refusal, in order.
def kinds(refusals)
  map(kind, refusals)
end

# nil when there is nothing to refuse; otherwise throws one error whose kind
# is the first refusal's and whose message joins every refusal's why.
def refuse(refusals)
  if is_empty(refusals) == false
    raise(kind(first(refusals)), join(map(why, refusals), "; "))
  end
  nil
end

def ledger_row(k, meaning, status, retry)
  {kind: k, meaning:, exit_status: status, retryable: retry}
end

def ledger()
  [
    ledger_row(:usage, "the call or command line is wrong", 64, false),
    ledger_row(
      :bad_option,
      "an option is unknown or has a bad value",
      64,
      false
    ),
    ledger_row(:bad_key, "a key is malformed", 64, false),
    ledger_row(:parse_error, "text does not parse", 65, false),
    ledger_row(:decode_error, "bytes do not decode", 65, false),
    ledger_row(:render_error, "a value does not render", 65, false),
    ledger_row(:query_error, "a query is malformed", 65, false),
    ledger_row(:tampered, "a verdict or digest does not match", 65, false),
    ledger_row(:not_found, "the thing asked for is absent", 66, false),
    ledger_row(:breaker_open, "a circuit breaker is open", 69, true),
    ledger_row(:exists, "the thing to create is already there", 73, false),
    ledger_row(:conflict, "a concurrent change won", 75, true),
    ledger_row(:timeout, "the deadline passed", 75, true),
    ledger_row(:hold, "held for now; try again later", 75, true),
    ledger_row(:denied, "the caller may not do this", 77, false),
    ledger_row(:permission_denied, "the system refused access", 77, false),
    ledger_row(:expired, "the grant is past its time", 77, false),
    ledger_row(:revoked, "the grant was withdrawn", 77, false),
    ledger_row(:untrusted, "the source is not trusted", 77, false),
    ledger_row(:escapes_root, "a path leaves its root", 77, false),
    ledger_row(:refused, "one or more rules found fault", 1, false),
    ledger_row(:command_failed, "a command exited non-zero", 1, false),
    ledger_row(:command_not_found, "a command is not on the path", 127, false)
  ]
end

def ledger_entry(k)
  e = find_first((r) -> get(r, :kind) == k, ledger)
  if e.nil?
    raise(:not_found, "no ledger kind #{k}")
  end
  e
end

def exit_status(k)
  get(ledger_entry(k), :exit_status)
end

def retryable?(k)
  get(ledger_entry(k), :retryable)
end

def findings(subject, rules)
  flat_map((rule) -> rule(subject), rules)
end

def enforce(subject, rules, opts)
  found = findings(subject, rules)
  if is_empty(found) == false
    raise(
      get(opts, :kind) or :refused,
      join(map(why, found), "; "),
      {data: found}
    )
  end
  nil
end

def ok(v)
  {ok: true, value: v}
end

def refused(r)
  {ok: false, refusal: r}
end

def ok?(result)
  get(result, :ok) == true
end

def value(result)
  if ok?(result)
    get(result, :value)
  end
end

def refusal_of(result)
  if ok?(result)
    nil
  else
    get(result, :refusal)
  end
end

def standing(xs, marks)
  map(
    (i) -> nth(i, xs),
    filter((i) -> is_empty(nth(i, marks)), range(0, size(xs)))
  )
end

test "what stands is every entry refused for nothing, in order"
  assert standing([], []) == []
  assert standing(["a", "b", "c"], [[], [refusal(:x, "no")], []]) == ["a", "c"]
  assert standing(["a"], [[]]) == ["a"]
  assert standing(["a", "b"], [[refusal(:x, "1")], [refusal(:y, "2")]]) == []
end

test "a result carries a value or a refusal, never both"
  a = ok(3)
  assert ok?(a) == true
  assert value(a) == 3
  assert refusal_of(a).nil?
  b = refused(refusal(:late, "after noon"))
  assert ok?(b) == false
  assert value(b).nil?
  assert kind(refusal_of(b)) == :late
  assert ok?({}) == false
  assert value(ok(nil)).nil?
end

test "a refusal is its kind and its why"
  r = refusal(:too_big, "3 > 2")
  assert r == [:too_big, "3 > 2"]
  assert kind(r) == :too_big
  assert why(r) == "3 > 2"
  assert kinds([r, refusal(:bad, "no")]) == [:too_big, :bad]
  assert kinds([]) == []
end

test "refuse passes nothing and throws everything, kind first"
  assert refuse([]).nil?
  caught = begin
    refuse([refusal(:a, "one"), refusal(:b, "two")])
  rescue e
    e
  end
  assert error?(caught) == true
end

test "the ledger is closed: one row per kind, each with a status and a retry mark"
  rows = ledger
  assert size(rows) == size(kinds(map((r) -> [get(r, :kind), ""], rows)))
  assert size(filter((r) -> get(r, :kind) == :refused, rows)) == 1
  assert size(filter((r) -> is_empty(get(r, :meaning)), rows)) == 0
  assert exit_status(:not_found) == 66
  assert exit_status(:usage) == 64
  assert exit_status(:hold) == 75
  assert exit_status(:command_not_found) == 127
end

test "a retryable kind is the transient ones, and an unknown kind is refused"
  assert retryable?(:timeout) == true
  assert retryable?(:conflict) == true
  assert retryable?(:not_found) == false
  assert retryable?(:tampered) == false
  caught = begin
    exit_status(:nonesuch)
  rescue e
    e
  end
  assert error?(caught) == true
  assert caught.kind == :not_found
end

test "enforce passes a sound subject and raises every finding at once"
  small = (n) -> filter((_) -> n > 2, [refusal(:too_big, "#{n} > 2")])
  odd = (n) -> filter((_) -> n % 2 == 1, [refusal(:odd, "#{n} is odd")])
  assert enforce(2, [small, odd], {}).nil?
  assert enforce(2, [], {}).nil?
  caught = begin
    enforce(5, [small, odd], {})
  rescue e
    e
  end
  assert caught.kind == :refused
  assert caught.message == "5 > 2; 5 is odd"
  assert kinds(caught.data) == [:too_big, :odd]
  named = begin
    enforce(5, [small], {kind: :usage})
  rescue e
    e
  end
  assert named.kind == :usage
end
