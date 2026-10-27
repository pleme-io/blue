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
    parent[:trace_id]
  end
  parent_id = if parent.nil?
    nil
  else
    parent[:id]
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
  parent = (attrs or {})[:parent]
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
  base = merge(s, {duration_ns: elapsed_since(s[:started_ns])})
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
  sink = (attrs or {})[:sink]
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
    outcome[1]
  end
  emit(closed(s, failure), attrs)
  if failure != nil
    raise(failure)
  end
  outcome[1]
end

@doc """
otlp_endpoint: where spans ship: observe's otlp_endpoint, else OTEL_EXPORTER_OTLP_ENDPOINT; nil when observe turns traces off.

    otlp_endpoint({traces: :off}) #=> nil
"""
def otlp_endpoint(observe)
  if rogu::on?(observe, :traces)
    rogu::given((observe or {})[:otlp_endpoint]) or
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

@doc """
otlp_status: a span's OTLP status: code 1 when ok, code 2 with the error's message.

    otlp_status({status: :ok}) #=> {code: 1}
"""
def otlp_status(s)
  if s[:status] == :ok
    {code: 1}
  else
    {code: 2, message: s[:error][:message]}
  end
end

@doc """
otlp_span: a closed span record as an OTLP/JSON span.

    get(otlp_span({name: "a", trace_id: "t", id: "i", parent_id: nil, started_ns: 1, duration_ns: 2, attrs: {}, status: :ok}), :endTimeUnixNano) #=> "3"
"""
def otlp_span(s)
  {
    traceId: s[:trace_id],
    spanId: s[:id],
    parentSpanId: s[:parent_id] or "",
    name: s[:name],
    kind: 1,
    startTimeUnixNano: to_s(s[:started_ns]),
    endTimeUnixNano: to_s(s[:started_ns] + s[:duration_ns]),
    attributes: map((e) -> attribute(first(e), e[1]), map_entries(s[:attrs])),
    status: otlp_status(s)
  }
end

@doc """
otlp_body: the OTLP/JSON export request for spans of one service.

    get(first(get(first(get(otlp_body("s", []), :resourceSpans)), :scopeSpans)), :spans) #=> []
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

    ship("http://127.0.0.1:1", "s", []) #=> false
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

    exporter({traces: :off}, "s")(1) #=> nil
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
    (sink) -> assert span("work", (s) -> s[:name], {sink:}) == "work"
  )
  assert retsu::size(records) == 1
end

test "span emits one closed record: name, ids, attrs, start, duration, status ok"
  records = collect((sink) -> span("fetch", (_s) -> 1, {sink:, url: "u"}))
  r = first(records)
  assert r[:name] == "fetch"
  assert r[:attrs] == {url: "u"}
  assert r[:status] == :ok
  assert r[:parent_id].nil?
  assert string?(r[:trace_id]) and retsu::size(chars(r[:trace_id])) == 32
  assert retsu::size(chars(r[:id])) == 16
  assert r[:duration_ns] >= 0
  assert r[:started_ns] > 0
  assert has?(r, :error) == false
end

test "span gives the function the same ids the record carries"
  seen = [nil]
  records = collect((sink) -> span("a", (s) -> set!(seen, [s]), {sink:}))
  assert first(seen)[:id] == first(records)[:id]
  assert first(seen)[:trace_id] == first(records)[:trace_id]
  assert first(seen)[:name] == "a"
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
  outer = records[1]
  assert inner[:name] == "inner"
  assert inner[:parent_id] == outer[:id]
  assert inner[:trace_id] == outer[:trace_id]
  assert inner[:id] != outer[:id]
  assert outer[:parent_id].nil?
  assert has?(inner[:attrs], :parent) == false
end

test "two root spans start two traces"
  records = collect(
    (sink) -> [span("a", (_s) -> 1, {sink:}), span("a", (_s) -> 1, {sink:})]
  )
  assert first(records)[:trace_id] != records[1][:trace_id]
end

test "span records an error, emits it, and raises the same error again"
  seen = [[]]
  sink = (s) -> set!(seen, [append(first(seen), [s])])
  assert raises?(:oops, () -> span("bad", (_s) -> raise(:oops, "no"), {sink:}))
  r = first(first(seen))
  assert r[:status] == :error
  assert r[:error] == {kind: :oops, message: "no"}
  assert r[:duration_ns] >= 0
end

test "span with nil attrs has none and writes through rogu when it has no sink"
  assert span("quiet", (_s) -> 7, nil) == 7
  assert span("quiet", (_s) -> 7, {}) == 7
end

test "span keeps the attrs it was given, minus its own two keys"
  records = collect(
    (sink) -> span("a", (_s) -> nil, {sink:, user: 1, kind: "x"})
  )
  assert first(records)[:attrs] == {kind: "x", user: 1}
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
  assert o[:traceId] == r[:trace_id]
  assert o[:spanId] == r[:id]
  assert o[:parentSpanId] == ""
  assert o[:status] == {code: 1}
  assert o[:attributes] == [{key: "n", value: {intValue: "3"}}]
  assert to_int(o[:endTimeUnixNano]) - to_int(o[:startTimeUnixNano]) ==
    r[:duration_ns]
  failed = otlp_span(
    merge(r, {status: :error, error: {kind: :x, message: "no"}})
  )
  assert failed[:status] == {code: 2, message: "no"}
end

test "the export body names the service once for every span"
  b = json_read(json_stringify(otlp_body("orders", [])))
  rs = first(b["resourceSpans"])
  assert first(rs["resource"]["attributes"])["key"] == "service.name"
  assert first(rs["scopeSpans"])["spans"] == []
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
  assert req[:path] == "/v1/traces"
  rs = first(json_read(req[:body])["resourceSpans"])
  sp = first(first(rs["scopeSpans"])["spans"])
  assert sp["name"] == "work"
end

test "a failed trace export is reported, not raised"
  assert ship("http://127.0.0.1:1", "s", []) == false
end
