use("jisho", [:delete, :has?, :merge])
use("moji", [:take_chars])
use("retsu", [:first])
use("rogu")
use("tesuto", [:raises?])

def reserved()
  [:parent, :sink]
end

def attributes(attrs)
  given = attrs or {}
  if not map?(given)
    raise(:bad_option, "span attrs are a record, got #{to_s(given)}")
  end
  reduce((acc, k) -> delete(acc, k), given, reserved)
end

def lineage(name, started, parent)
  trace = if parent.nil?
    take_chars(blake3_hex("#{name}/#{to_s(started)}"), 32)
  else
    get(parent, :trace_id)
  end
  parent_id = if parent.nil?
    nil
  else
    get(parent, :id)
  end
  {
    trace_id: trace,
    id: take_chars(
      blake3_hex("#{trace}/#{name}/#{to_s(started)}/#{to_s(parent_id)}"),
      16
    ),
    parent_id:
  }
end

def opened(name, attrs, started)
  clean = attributes(attrs)
  parent = get(attrs or {}, :parent)
  if parent != nil and
      not (map?(parent) and has?(parent, :trace_id) and has?(parent, :id))
    raise(:bad_option, "span parent: is the span record its function was given")
  end
  merge(
    {name:, attrs: clean, started_ns: started},
    lineage(name, started, parent)
  )
end

def closed(s, error)
  base = merge(s, {duration_ns: elapsed_since(get(s, :started_ns))})
  if error.nil?
    merge(base, {status: :ok})
  else
    merge(
      base,
      {status: :error, error: {kind: error.kind, message: error.message}}
    )
  end
end

def emit(s, attrs)
  sink = get(attrs or {}, :sink)
  if sink.nil?
    rogu::info("span", s)
  else
    sink(s)
  end
  nil
end

def attempt(f, s)
  [:returned, f(s)]
rescue e
  [:raised, e]
end

@doc """
span: run f inside a named span.
"""
def span(name, f, attrs)
  if not string?(name) or name == ""
    raise(:bad_option, "a span takes a name: non-empty text")
  end
  s = opened(name, attrs, now_ns)
  outcome = attempt(f, s)
  failure = if first(outcome) == :raised
    nth(1, outcome)
  end
  emit(closed(s, failure), attrs)
  if failure != nil
    raise(failure)
  end
  nth(1, outcome)
end

def collect(f)
  seen = [[]]
  sink = (s) -> set!(seen, [append(first(seen), [s])])
  f(sink)
  first(seen)
end

test "span returns the value of its function and hands it the open span"
  records = collect(
    (sink) -> assert span("work", (s) -> get(s, :name), {sink:}) == "work"
  )
  assert retsu::size(records) == 1
end

test "span emits one closed record: name, ids, attrs, start, duration, status ok"
  records = collect((sink) -> span("fetch", (_s) -> 1, {sink:, url: "u"}))
  r = first(records)
  assert get(r, :name) == "fetch"
  assert get(r, :attrs) == {url: "u"}
  assert get(r, :status) == :ok
  assert get(r, :parent_id).nil?
  assert string?(get(r, :trace_id)) and
    retsu::size(chars(get(r, :trace_id))) == 32
  assert retsu::size(chars(get(r, :id))) == 16
  assert get(r, :duration_ns) >= 0
  assert get(r, :started_ns) > 0
  assert has?(r, :error) == false
end

test "span gives the function the same ids the record carries"
  seen = [nil]
  records = collect((sink) -> span("a", (s) -> set!(seen, [s]), {sink:}))
  assert get(first(seen), :id) == get(first(records), :id)
  assert get(first(seen), :trace_id) == get(first(records), :trace_id)
  assert get(first(seen), :name) == "a"
end

test "a child span names its parent and shares the trace"
  records = collect(
    fn(sink)
      span(
        "outer",
        (o) -> span("inner", (_i) -> 1, {sink:, parent: o}),
        {sink:}
      )
    end
  )
  inner = first(records)
  outer = nth(1, records)
  assert get(inner, :name) == "inner"
  assert get(inner, :parent_id) == get(outer, :id)
  assert get(inner, :trace_id) == get(outer, :trace_id)
  assert get(inner, :id) != get(outer, :id)
  assert get(outer, :parent_id).nil?
  assert has?(get(inner, :attrs), :parent) == false
end

test "two root spans start two traces"
  records = collect(
    (sink) -> [span("a", (_s) -> 1, {sink:}), span("a", (_s) -> 1, {sink:})]
  )
  assert get(first(records), :trace_id) != get(nth(1, records), :trace_id)
end

test "span records an error, emits it, and raises the same error again"
  seen = [[]]
  sink = (s) -> set!(seen, [append(first(seen), [s])])
  assert raises?(:oops, () -> span("bad", (_s) -> raise(:oops, "no"), {sink:}))
  r = first(first(seen))
  assert get(r, :status) == :error
  assert get(r, :error) == {kind: :oops, message: "no"}
  assert get(r, :duration_ns) >= 0
end

test "span with nil attrs has none and writes through rogu when it has no sink"
  assert span("quiet", (_s) -> 7, nil) == 7
  assert span("quiet", (_s) -> 7, {}) == 7
end

test "span keeps the attrs it was given, minus its own two keys"
  records = collect(
    (sink) -> span("a", (_s) -> nil, {sink:, user: 1, kind: "x"})
  )
  assert get(first(records), :attrs) == {kind: "x", user: 1}
end

test "span refuses a bad name, a bad attrs, a bad parent, and runs nothing then"
  ran = [false]
  f = (_s) -> set!(ran, [true])
  assert raises?(:bad_option, () -> span("", f, {}))
  assert raises?(:bad_option, () -> span(:a, f, {}))
  assert raises?(:bad_option, () -> span(nil, f, {}))
  assert raises?(:bad_option, () -> span("a", f, [1]))
  assert raises?(:bad_option, () -> span("a", f, {parent: 5}))
  assert raises?(:bad_option, () -> span("a", f, {parent: {id: "x"}}))
  assert raises?(:bad_option, () -> span("a", f, {parent: {trace_id: "x"}}))
  assert first(ran) == false
end
