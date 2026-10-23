use("jisho")
use("moji", [:checked])
use("retsu", [:count_where, :enumerate, :first, :is_empty, :rest, :zip])
use("tesuto", [:raises?])

def name_ok?(name)
  string?(name) and name != "" and not contains?(name, " ")
end

def label_names(opts)
  declared = get(opts, :labels)
  if declared.nil?
    nil
  elsif list?(declared) and
      count_where(name_ok?, map(to_s, declared)) == retsu::size(declared)
    map(to_s, declared)
  else
    raise(:bad_option, "labels: takes a list of label names")
  end
end

def instrument(kind, name, bounds, opts)
  checked(opts, [:help, :labels])
  if not name_ok?(name)
    raise(:bad_option, "an instrument takes a name: text with no space")
  end
  state = {kind:, bounds:, series: {}}
  {
    kind:,
    name:,
    help: get(opts, :help) or "",
    labels: label_names(opts),
    bounds:,
    pid: spawn_server(handle, state)
  }
end

def counter(name, opts)
  instrument(:counter, name, nil, opts)
end

def gauge(name, opts)
  instrument(:gauge, name, nil, opts)
end

def increasing?(xs)
  retsu::size(xs) < 2 or nth(0, xs) < nth(1, xs) and increasing?(drop(1, xs))
end

def histogram(name, bounds, opts)
  if not list?(bounds) or
      is_empty(bounds) or
      count_where(number?, bounds) != retsu::size(bounds) or
      not increasing?(bounds)
    raise(
      :bad_option,
      "a histogram takes bounds: numbers, increasing, at least one"
    )
  end
  instrument(:histogram, name, bounds, opts)
end

def labels_of(i, labels)
  given = labels or {}
  declared = get(i, :labels)
  names = map(to_s, jisho::keys(given))
  if declared != nil and
      count_where((n) -> member?(n, declared), names) != retsu::size(names)
    raise(
      :bad_option,
      "#{get(i, :name)} takes the labels #{join(declared, ", ")}"
    )
  end
  reduce(
    (acc, e) -> assoc(acc, to_s(first(e)), to_s(nth(1, e))),
    {},
    map_entries(given)
  )
end

def slot(bounds, value)
  count_where((b) -> value > b, bounds)
end

def bump(counts, at)
  map(
    fn(p)
      if first(p) == at
        nth(1, p) + 1
      else
        nth(1, p)
      end
    end,
    enumerate(counts)
  )
end

def fresh(state)
  if get(state, :kind) == :histogram
    {counts: map((_b) -> 0, append(get(state, :bounds), [0])), sum: 0, count: 0}
  else
    {value: 0}
  end
end

def apply_to(state, entry, msg)
  op = first(msg)
  if op == :add
    assoc(entry, :value, get(entry, :value) + nth(3, msg))
  elsif op == :set
    assoc(entry, :value, nth(3, msg))
  else
    value = nth(3, msg)
    {
      counts: bump(get(entry, :counts), slot(get(state, :bounds), value)),
      sum: get(entry, :sum) + value,
      count: get(entry, :count) + 1
    }
  end
end

def handle(msg, state)
  if first(msg) == :read
    send(nth(1, msg), [:series, self, get(state, :series)])
    state
  else
    key = nth(1, msg)
    old = get(get(state, :series), key) or
      {labels: nth(2, msg), entry: fresh(state)}
    entry = apply_to(state, get(old, :entry), msg)
    assoc(
      state,
      :series,
      assoc(get(state, :series), key, {labels: nth(2, msg), entry:})
    )
  end
end

def send_to(i, op, labels, value)
  clean = labels_of(i, labels)
  send(get(i, :pid), [op, to_s(clean), clean, value])
  nil
end

def need_kind(i, kind, verb)
  if get(i, :kind) != kind
    raise(
      :bad_option,
      "#{verb} takes a #{to_s(kind)}, got a #{to_s(get(i, :kind))}"
    )
  end
end

def need_number(value, verb)
  if not number?(value)
    raise(:bad_option, "#{verb} takes a number, got #{to_s(value)}")
  end
end

def increase(c, by, labels)
  need_kind(c, :counter, "increase")
  need_number(by, "increase")
  if by < 0
    raise(
      :bad_option,
      "a counter only goes up: increase takes 0 or more, got #{to_s(by)}"
    )
  end
  send_to(c, :add, labels, by)
end

def put(g, value, labels)
  need_kind(g, :gauge, "put")
  need_number(value, "put")
  send_to(g, :set, labels, value)
end

def observe(h, value, labels)
  need_kind(h, :histogram, "observe")
  need_number(value, "observe")
  send_to(h, :record, labels, value)
end

def tick(opts)
  clock = get(opts, :clock)
  if clock.nil?
    now_ms
  else
    clock()
  end
end

def attempt(f)
  [:returned, f()]
rescue e
  [:raised, e]
end

def measure(h, f, opts)
  checked(opts, [:labels, :clock])
  need_kind(h, :histogram, "measure")
  started = tick(opts)
  outcome = attempt(f)
  observe(h, (tick(opts) - started) / 1000, get(opts, :labels))
  if first(outcome) == :raised
    raise(nth(1, outcome))
  end
  nth(1, outcome)
end

def fetch(i, wait)
  pid = get(i, :pid)
  send(pid, [:read, self])
  reply = receive([:series, pid, :_], wait, nil)
  if reply.nil?
    raise(:timeout, "#{get(i, :name)} did not answer")
  end
  nth(2, reply)
end

def sample(name, labels, value)
  {name:, labels:, value:}
end

def cumulative(counts)
  nth(
    1,
    reduce(
      (acc, c) -> [first(acc) + c, append(nth(1, acc), [first(acc) + c])],
      [0, []],
      counts
    )
  )
end

def histogram_samples(i, labels, entry)
  name = get(i, :name)
  edges = append(map(to_s, get(i, :bounds)), ["+Inf"])
  buckets = map(
    (p) -> sample("#{name}_bucket", assoc(labels, "le", first(p)), nth(1, p)),
    zip(edges, cumulative(get(entry, :counts)))
  )
  append(
    buckets,
    [
      sample("#{name}_sum", labels, get(entry, :sum)),
      sample("#{name}_count", labels, get(entry, :count))
    ]
  )
end

def series_samples(i, row)
  labels = get(row, :labels)
  entry = get(row, :entry)
  if get(i, :kind) == :histogram
    histogram_samples(i, labels, entry)
  else
    [sample(get(i, :name), labels, get(entry, :value))]
  end
end

def wanted?(labels, want)
  count_where((e) -> get(labels, first(e)) == nth(1, e), map_entries(want)) ==
    retsu::size(map_entries(want))
end

def read(i, opts)
  checked(opts, [:labels, :wait_ms])
  want = labels_of(i, get(opts, :labels))
  rows = filter(
    (r) -> wanted?(get(r, :labels), want),
    jisho::values(fetch(i, get(opts, :wait_ms) or 5000))
  )
  append(*map((r) -> series_samples(i, r), rows))
end

def values_of(samples)
  map((s) -> get(s, :value), samples)
end

test "counter declares an instrument and starts with no series"
  c = counter("requests_total", {help: "Requests."})
  assert get(c, :kind) == :counter
  assert get(c, :name) == "requests_total"
  assert get(c, :help) == "Requests."
  assert read(c, {}) == []
  assert get(counter("n", {}), :help) == ""
end

test "counter refuses a bad name, an unknown option and bad labels"
  assert raises?(:bad_option, () -> counter("", {}))
  assert raises?(:bad_option, () -> counter("two words", {}))
  assert raises?(:bad_option, () -> counter(:sym, {}))
  assert raises?(:bad_option, () -> counter("n", {unit: "s"}))
  assert raises?(:bad_option, () -> counter("n", {labels: "a"}))
  assert raises?(:bad_option, () -> counter("n", {labels: ["a b"]}))
end

test "increase adds, per label set, and returns nil"
  c = counter("hits", {})
  assert increase(c, 1, {}).nil?
  increase(c, 2, {})
  increase(c, 5, {path: "/a"})
  increase(c, 1, {path: "/a"})
  increase(c, 4, {path: "/b"})
  assert read(c, {}) ==
    [
      {name: "hits", labels: {"path" => "/a"}, value: 6},
      {name: "hits", labels: {"path" => "/b"}, value: 4},
      {name: "hits", labels: {}, value: 3}
    ]
end

test "increase treats nil labels as none and text and keyword labels as one series"
  c = counter("hits", {})
  increase(c, 1, nil)
  increase(c, 1, {})
  increase(c, 1, {code: 200})
  increase(c, 1, {"code" => "200"})
  assert values_of(read(c, {})) == [2, 2]
end

test "increase by zero creates the series and a counter never goes down"
  c = counter("hits", {})
  increase(c, 0, {})
  assert values_of(read(c, {})) == [0]
  assert raises?(:bad_option, () -> increase(c, -1, {}))
  assert values_of(read(c, {})) == [0]
  assert increase(c, 1.5, {}).nil?
  assert values_of(read(c, {})) == [1.5]
end

test "increase refuses a non-number, another kind and an undeclared label"
  c = counter("hits", {labels: ["path"]})
  assert raises?(:bad_option, () -> increase(c, "1", {}))
  assert raises?(:bad_option, () -> increase(c, nil, {}))
  assert raises?(:bad_option, () -> increase(c, 1, {host: "a"}))
  assert increase(c, 1, {path: "/a"}).nil?
  assert raises?(:bad_option, () -> increase(gauge("g", {}), 1, {}))
  assert raises?(:bad_option, () -> increase(histogram("h", [1], {}), 1, {}))
end

test "put sets a gauge, replaces the value, and allows negatives"
  g = gauge("queue_depth", {})
  assert put(g, 4, {}).nil?
  put(g, 9, {})
  put(g, -2, {shard: "a"})
  assert read(g, {}) ==
    [
      {name: "queue_depth", labels: {"shard" => "a"}, value: -2},
      {name: "queue_depth", labels: {}, value: 9}
    ]
  put(g, 0, {})
  assert values_of(read(g, {})) == [-2, 0]
end

test "put refuses a non-number, another kind and an undeclared label"
  g = gauge("g", {labels: ["shard"]})
  assert raises?(:bad_option, () -> put(g, "x", {}))
  assert raises?(:bad_option, () -> put(g, 1, {zone: "a"}))
  assert raises?(:bad_option, () -> put(counter("c", {}), 1, {}))
end

test "read filters by labels and refuses an unknown option"
  c = counter("hits", {})
  increase(c, 1, {path: "/a", code: 200})
  increase(c, 2, {path: "/a", code: 500})
  increase(c, 4, {path: "/b", code: 200})
  assert values_of(read(c, {labels: {path: "/a"}})) == [1, 2]
  assert values_of(read(c, {labels: {code: 200}})) == [1, 4]
  assert values_of(read(c, {labels: {path: "/a", code: 500}})) == [2]
  assert read(c, {labels: {path: "/zzz"}}) == []
  assert retsu::size(read(c, {})) == 3
  assert raises?(:bad_option, () -> read(c, {since: 1}))
end

test "read answers in label order whatever the order of writing"
  c = counter("hits", {})
  increase(c, 1, {k: "b"})
  increase(c, 1, {k: "a"})
  assert map((s) -> get(get(s, :labels), "k"), read(c, {})) == ["a", "b"]
end

test "two instruments keep their own series"
  a = counter("a", {})
  b = counter("b", {})
  increase(a, 1, {})
  increase(b, 10, {})
  assert values_of(read(a, {})) == [1]
  assert values_of(read(b, {})) == [10]
end

test "histogram refuses bounds that are not increasing numbers"
  assert raises?(:bad_option, () -> histogram("h", [], {}))
  assert raises?(:bad_option, () -> histogram("h", [1, 1], {}))
  assert raises?(:bad_option, () -> histogram("h", [2, 1], {}))
  assert raises?(:bad_option, () -> histogram("h", ["a"], {}))
  assert raises?(:bad_option, () -> histogram("h", nil, {}))
  assert get(histogram("h", [1], {}), :bounds) == [1]
end

test "observe fills cumulative buckets, a sum and a count"
  h = histogram("lat", [0.1, 0.5, 1], {})
  assert read(h, {}) == []
  assert observe(h, 0.05, {}).nil?
  observe(h, 0.1, {})
  observe(h, 0.3, {})
  observe(h, 7, {})
  samples = read(h, {})
  assert map((s) -> get(s, :name), samples) ==
    [
      "lat_bucket",
      "lat_bucket",
      "lat_bucket",
      "lat_bucket",
      "lat_sum",
      "lat_count"
    ]
  assert map((s) -> get(get(s, :labels), "le"), take(4, samples)) ==
    ["0.1", "0.5", "1", "+Inf"]
  assert values_of(samples) == [2, 3, 3, 4, 7.45, 4]
end

test "observe keeps a series per label set and refuses what it cannot record"
  h = histogram("lat", [1], {labels: ["route"]})
  observe(h, 0.5, {route: "a"})
  observe(h, 2, {route: "b"})
  assert values_of(read(h, {labels: {route: "a"}})) == [1, 1, 0.5, 1]
  assert values_of(read(h, {labels: {route: "b"}})) == [0, 1, 2, 1]
  assert raises?(:bad_option, () -> observe(h, "x", {route: "a"}))
  assert raises?(:bad_option, () -> observe(h, 1, {zone: "a"}))
  assert raises?(:bad_option, () -> observe(gauge("g", {}), 1, {}))
end

def hand_out(requester, times)
  send(requester, [:time, first(times)])
  rest(times)
end

def fake_clock(times)
  pid = spawn_server(hand_out, times)
  () -> ask_time(pid)
end

def ask_time(pid)
  send(pid, self)
  nth(1, receive([:time, :_]))
end

test "measure records the seconds f took and returns its value"
  h = histogram("took", [1, 10], {})
  clock = fake_clock([1000, 3500])
  assert measure(h, () -> 42, {clock:}) == 42
  assert values_of(read(h, {})) == [0, 1, 1, 2.5, 1]
end

test "measure puts a fast call in the first bucket and a slow one past the last"
  h = histogram("took", [1, 10], {})
  measure(h, () -> nil, {clock: fake_clock([0, 400])})
  measure(h, () -> nil, {clock: fake_clock([0, 60000])})
  assert values_of(read(h, {})) == [1, 1, 2, 60.4, 2]
end

test "measure records when f raises, and raises the same error again"
  h = histogram("took", [1], {})
  clock = fake_clock([0, 2000])
  assert raises?(:oops, () -> measure(h, () -> raise(:oops, "no"), {clock:}))
  assert values_of(read(h, {})) == [0, 1, 2, 1]
end

test "measure takes labels and refuses another kind and an unknown option"
  h = histogram("took", [1], {})
  measure(h, () -> 1, {labels: {job: "a"}})
  assert retsu::size(read(h, {labels: {job: "a"}})) == 4
  assert read(h, {labels: {job: "b"}}) == []
  assert raises?(:bad_option, () -> measure(h, () -> 1, {label: {}}))
  assert raises?(:bad_option, () -> measure(counter("c", {}), () -> 1, {}))
end

test "read raises a timeout when the instrument does not answer"
  c = counter("gone", {})
  dead = jisho::merge(c, {pid: spawn(() -> nil)})
  assert raises?(:timeout, () -> read(dead, {wait_ms: 50}))
  started = now_ms
  assert raises?(:timeout, () -> read(dead, {wait_ms: 1}))
  assert now_ms - started < 3000
  assert read(c, {wait_ms: 5000}) == []
end
