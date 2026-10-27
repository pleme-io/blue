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

@doc """
otlp_endpoint: where spans ship: observe's otlp_endpoint, else OTEL_EXPORTER_OTLP_ENDPOINT; nil when observe turns traces off.
"""
def otlp_endpoint(observe)
  if rogu::on?(observe, :traces)
    rogu::given(get(observe or {}, :otlp_endpoint)) or
      rogu::given(getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))
  end
end

@doc """
attribute: one OTLP key-value: integers as intValue, booleans as boolValue, the rest as text.

    attribute(:n, 2) #=> {key: "n", value: {intValue: "2"}}
"""
def attribute(k, v)
  value = if integer?(v)
    {intValue: to_s(v)}
  elsif boolean?(v)
    {boolValue: v}
  else
    {stringValue: to_s(v)}
  end
  {key: to_s(k), value:}
end

def otlp_status(s)
  if get(s, :status) == :ok
    {code: 1}
  else
    {code: 2, message: get(get(s, :error), :message)}
  end
end

@doc """
otlp_span: a closed span record as an OTLP/JSON span.
"""
def otlp_span(s)
  {
    traceId: get(s, :trace_id),
    spanId: get(s, :id),
    parentSpanId: get(s, :parent_id) or "",
    name: get(s, :name),
    kind: 1,
    startTimeUnixNano: to_s(get(s, :started_ns)),
    endTimeUnixNano: to_s(get(s, :started_ns) + get(s, :duration_ns)),
    attributes: map(
      (e) -> attribute(first(e), nth(1, e)),
      map_entries(get(s, :attrs))
    ),
    status: otlp_status(s)
  }
end

@doc """
otlp_body: the OTLP/JSON export request for spans of one service.
"""
def otlp_body(service, spans)
  {
    resourceSpans: [
      {
        resource: {attributes: [attribute("service.name", service)]},
        scopeSpans: [{scope: {name: "tsuiseki"}, spans: map(otlp_span, spans)}]
      }
    ]
  }
end

@doc """
ship: POST spans to an OTLP/HTTP collector's /v1/traces; a failure is logged, never raised.
"""
def ship(url, service, spans)
  http_request(
    "POST",
    "#{url}/v1/traces",
    {"Content-Type" => "application/json"},
    json_stringify(otlp_body(service, spans)),
    1000
  )
  true
rescue e
  rogu::warn("trace export failed", {error: e, endpoint: url})
  false
end

@doc """
exporter: the span sink observe asks for: OTLP/HTTP when traces are on and an endpoint is known, a sink that drops when traces are :off, else nil (rogu).
"""
def exporter(observe, service)
  if not rogu::on?(observe, :traces)
    (_s) -> nil
  else
    url = otlp_endpoint(observe)
    if url != nil
      (s) -> ship(url, service, [s])
    end
  end
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

test "attributes carry integers, booleans and text in their OTLP fields"
  assert attribute(:n, 2) == {key: "n", value: {intValue: "2"}}
  assert attribute("ok", true) == {key: "ok", value: {boolValue: true}}
  assert attribute(:u, :x) == {key: "u", value: {stringValue: "x"}}
end

test "a closed span becomes an OTLP span with its ids, times and status"
  records = collect((sink) -> span("fetch", (_s) -> 1, {sink:, n: 3}))
  r = first(records)
  o = otlp_span(r)
  assert get(o, :traceId) == get(r, :trace_id)
  assert get(o, :spanId) == get(r, :id)
  assert get(o, :parentSpanId) == ""
  assert get(o, :status) == {code: 1}
  assert get(o, :attributes) == [{key: "n", value: {intValue: "3"}}]
  assert to_int(get(o, :endTimeUnixNano)) -
    to_int(get(o, :startTimeUnixNano)) == get(r, :duration_ns)
  failed = otlp_span(
    merge(r, {status: :error, error: {kind: :x, message: "no"}})
  )
  assert get(failed, :status) == {code: 2, message: "no"}
end

test "the export body names the service once for every span"
  b = json_read(json_stringify(otlp_body("orders", [])))
  rs = first(get(b, "resourceSpans"))
  assert get(first(get(get(rs, "resource"), "attributes")), "key") ==
    "service.name"
  assert get(first(get(rs, "scopeSpans")), "spans") == []
end

test "traces off drops spans, and no endpoint leaves the rogu default"
  assert exporter({traces: :off, otlp_endpoint: "http://c"}, "s")(1).nil?
  assert otlp_endpoint({traces: :off, otlp_endpoint: "http://c"}).nil?
  assert exporter({otlp_endpoint: "http://c"}, "s") != nil
end

test "an exporting span POSTs OTLP JSON to /v1/traces"
  l = http_listen("127.0.0.1:0")
  url = "http://127.0.0.1:#{to_s(http_listener_port(l))}"
  me = self
  spawn(
    fn()
      span("work", (_s) -> 1, {sink: exporter({otlp_endpoint: url}, "orders")})
      send(me, :done)
    end
  )
  receive(:_, 2000, :none)
  req = http_next_request(l, 500)
  assert get(req, :path) == "/v1/traces"
  rs = first(get(json_read(get(req, :body)), "resourceSpans"))
  sp = first(get(first(get(rs, "scopeSpans")), "spans"))
  assert get(sp, "name") == "work"
end

test "a failed trace export is reported, not raised"
  assert ship("http://127.0.0.1:1", "s", []) == false
end
