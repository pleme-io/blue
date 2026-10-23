use("retsu", [:contains, :find_first, :first, :flat_map, :is_empty, :size])

# kyohi (拒否) — refusals, as data.
#
# A refusal is `[kind, why]`: a keyword naming what was refused and the reason,
# usually text. A check that can fail several ways at once returns EVERY
# refusal it finds, as a list, instead of throwing on the first, so a caller
# sees the whole picture and can test for one kind. `check` returns that list
# (empty when the subject is sound); `enforce` is its raising form and turns
# the list into one thrown error when the caller wants to stop.
#
# kueri, kinji and nisshi each wrote this vocabulary. It lives here once;
# their names are bridges to these (`legacy_names`) until each package's 0.2.0.

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

def check(subject, rules)
  flat_map(rules, (rule) -> rule(subject))
end

def raised_kind(want, found)
  if want == :first
    kind(first(found))
  else
    want or :refused
  end
end

def enforce(subject, rules, opts?)
  opts = opts or {}
  found = check(subject, rules)
  if is_empty(found) == false
    raise(
      raised_kind(get(opts, :kind), found),
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

test "check returns every finding of every rule, in rule order, and never raises"
  small = (n) -> filter((_) -> n > 2, [refusal(:too_big, "#{n} > 2")])
  odd = (n) -> filter((_) -> n % 2 == 1, [refusal(:odd, "#{n} is odd")])
  assert check(2, [small, odd]) == []
  assert check(2, []) == []
  assert check(5, []) == []
  assert check(1, [small, odd]) == [refusal(:odd, "1 is odd")]
  assert check(5, [small, odd]) ==
    [refusal(:too_big, "5 > 2"), refusal(:odd, "5 is odd")]
  assert check(5, [odd, small]) ==
    [refusal(:odd, "5 is odd"), refusal(:too_big, "5 > 2")]
  assert check(5, [small, small]) ==
    [refusal(:too_big, "5 > 2"), refusal(:too_big, "5 > 2")]
  assert kinds(check(4, [small])) == [:too_big]
  assert check([], [(xs) -> xs]) == []
end

test "enforce passes a sound subject and returns nil"
  small = (n) -> filter((_) -> n > 2, [refusal(:too_big, "#{n} > 2")])
  odd = (n) -> filter((_) -> n % 2 == 1, [refusal(:odd, "#{n} is odd")])
  assert enforce(2, [small, odd], {}).nil?
  assert enforce(2, [], {}).nil?
  assert enforce(7, [], {kind: :usage}).nil?
  assert enforce(2, [small], {kind: :first}).nil?
end

test "enforce raises refused with every finding joined and carried as data"
  small = (n) -> filter((_) -> n > 2, [refusal(:too_big, "#{n} > 2")])
  odd = (n) -> filter((_) -> n % 2 == 1, [refusal(:odd, "#{n} is odd")])
  caught_by = fn(f)
    begin
      f()
    rescue e
      e
    end
  end
  caught = caught_by(() -> enforce(5, [small, odd], {}))
  assert error?(caught) == true
  assert caught.kind == :refused
  assert caught.message == "5 > 2; 5 is odd"
  assert kinds(caught.data) == [:too_big, :odd]
  assert caught.data == check(5, [small, odd])
  single = caught_by(() -> enforce(4, [small], {}))
  assert single.kind == :refused
  assert single.message == "4 > 2"
end

test "enforce takes the kind from opts, or the first finding's with :first"
  small = (n) -> filter((_) -> n > 2, [refusal(:too_big, "#{n} > 2")])
  odd = (n) -> filter((_) -> n % 2 == 1, [refusal(:odd, "#{n} is odd")])
  caught_by = fn(f)
    begin
      f()
    rescue e
      e
    end
  end
  named = caught_by(() -> enforce(5, [small], {kind: :usage}))
  assert named.kind == :usage
  assert named.message == "5 > 2"
  nil_kind = caught_by(() -> enforce(5, [small], {kind: nil}))
  assert nil_kind.kind == :refused
  first_kind = caught_by(() -> enforce(5, [odd, small], {kind: :first}))
  assert first_kind.kind == :odd
  assert first_kind.message == "5 is odd; 5 > 2"
  assert kinds(first_kind.data) == [:odd, :too_big]
  other = caught_by(() -> enforce(5, [small, odd], {kind: :first}))
  assert other.kind == :too_big
end

test "enforce raises exactly when check finds something"
  small = (n) -> filter((_) -> n > 2, [refusal(:too_big, "#{n} > 2")])
  odd = (n) -> filter((_) -> n % 2 == 1, [refusal(:odd, "#{n} is odd")])
  caught_by = fn(f)
    begin
      f()
    rescue e
      e
    end
  end
  every = [-3, 0, 1, 2, 3, 4, 5, 8]
  sound = map((n) -> is_empty(check(n, [small, odd])), every)
  quiet = map((n) -> caught_by(() -> enforce(n, [small, odd], {})).nil?, every)
  assert sound == quiet
  assert contains(sound, true) == true
  assert contains(sound, false) == true
end

test "enforce takes its options or none, and the raised kind follows"
  small = (n) -> filter((_) -> n > 2, [refusal(:too_big, "#{n} > 2")])
  assert enforce(2, [small]).nil?
  assert enforce(2, [small], nil).nil?
  assert enforce(2, []).nil?
  caught = begin
    enforce(5, [small])
  rescue e
    e
  end
  assert caught.kind == :refused
  assert caught.message == "5 > 2"
  by_nil = begin
    enforce(5, [small], nil)
  rescue e
    e
  end
  assert by_nil.kind == :refused
  named = begin
    enforce(5, [small], {kind: :usage})
  rescue e
    e
  end
  assert named.kind == :usage
end
