space("tsuiseki?", {status: :provisional})

verb(
  "tsuiseki?",
  "adopt",
  {
    kind: :pure,
    shape: "adopt(carrier) -> context",
    laterals: ["serialize", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "read trace context from headers or a message",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "carry",
  {
    kind: :pure,
    shape: "carry(span, carrier) -> carrier",
    laterals: ["serialize", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "write trace context into headers or a message",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "correlate",
  {
    kind: :effect,
    shape: "correlate(trace_id, sources) -> [record]",
    laterals: ["log", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "logs, metrics and spans that share one trace id",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "critical_path",
  {
    kind: :pure,
    shape: "critical_path(trace) -> [span]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "the chain of spans that sets the total duration",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "current",
  {
    kind: :pure,
    shape: "current() -> span or nil",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "the span active in this process or nil",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "compare two traces of one operation",
    wave: 3,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "event",
  {
    kind: :effect,
    shape: "event(span, name, attrs) -> nil",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "record a point-in-time event on a span",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "get",
  {
    kind: :effect,
    shape: "get(store, trace_id) -> trace or nil",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "one whole trace by id",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "link",
  {
    kind: :effect,
    shape: "link(span, other) -> nil",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "relate a span to another trace without parenthood",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "push",
  {
    kind: :effect,
    shape: "push(sink, spans, opts) -> nil",
    laterals: ["deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "send spans to a collector",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "put",
  {
    kind: :effect,
    shape: "put(span, key, value) -> nil",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "set an attribute on a span",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "query",
  {
    kind: :effect,
    shape: "query(store, question, opts) -> [trace]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "find traces by service, duration or attribute",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "read",
  {
    kind: :effect,
    shape: "read(source, opts) -> [span]",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "spans from a file or collector export",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "sample?",
  {
    kind: :pure,
    shape: "sample?(rule, context) -> Bool",
    laterals: ["ratelimit", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "decide whether a trace is recorded",
    wave: 2,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "span",
  {
    kind: :effect,
    shape: "span(name, f, attrs) -> value",
    laterals: ["error", "time", "trace"],
    fleet: "pleme-observability",
    today: "absent",
    meaning: "run f inside a named span",
    wave: 0,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "start",
  {
    kind: :effect,
    shape: "start(name, attrs) -> span",
    laterals: ["trace"],
    fleet: "pleme-observability",
    today: "absent",
    meaning: "open a span by hand",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "stop",
  {
    kind: :effect,
    shape: "stop(span, opts) -> nil",
    laterals: ["trace"],
    fleet: "pleme-observability",
    today: "absent",
    meaning: "close a span by hand; records an error status if given",
    wave: 1,
    origin: "F"
  }
)

verb(
  "tsuiseki?",
  "tree",
  {
    kind: :pure,
    shape: "tree(spans) -> tree",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "assemble spans into a parent-child tree",
    wave: 2,
    origin: "F"
  }
)

edge(
  "tsuiseki?::correlate",
  :composes,
  "rogu::query",
  "finds logs sharing the trace id"
)

edge(
  "tsuiseki?::correlate",
  :composes,
  "tsuiseki?::get",
  "joins the trace to them"
)

edge("tsuiseki?::span", :composes, "tsuiseki?::start", "start, run f, stop")
edge("tsuiseki?::span", :composes, "tsuiseki?::stop", "stop even when f raises")

edge(
  "tsuiseki?::get",
  :composes,
  "tsuiseki?::tree",
  "assembles the spans of a trace"
)

edge(
  "tsuiseki?::critical_path",
  :generalizes,
  "keikaku?::critical_path",
  "same law on spans"
)

edge(
  "tsuiseki?::query",
  :generalizes,
  "tsuiseki?::get",
  "finds traces, not one"
)

edge(
  "tsuiseki?::sample?",
  :guards,
  "tsuiseki?::start",
  "decides before a trace begins"
)

edge("tsuiseki?::carry", :inverse, "tsuiseki?::adopt", "context out and in")
edge("tsuiseki?::adopt", :inverse, "tsuiseki?::carry", "context out and in")
edge("tsuiseki?::read", :inverse, "tsuiseki?::push", "reads what push wrote")
edge("tsuiseki?::push", :inverse, "tsuiseki?::read", "reads what push wrote")
edge("tsuiseki?::stop", :inverse, "tsuiseki?::start", "open and close")
edge("tsuiseki?::start", :inverse, "tsuiseki?::stop", "open and close")
edge("tsuiseki?::diff", :pairs, "keisoku?::diff", "latency compared both ways")

edge(
  "tsuiseki?::stop",
  :pairs,
  "keisoku?::observe",
  "span length is a histogram sample"
)

edge("tsuiseki?::event", :pairs, "rogu::info", "an event may be a log line")
edge("tsuiseki?::sample?", :pairs, "rogu::sample?", "one rule shape in both")
edge("tsuiseki?::span", :pairs, "rogu::scope", "trace id lands in log fields")
edge("tsuiseki?::query", :pairs, "shougai?::get", "incident evidence")
edge("tsuiseki?::link", :pairs, "tsuiseki?::carry", "batch jobs link not nest")
edge("tsuiseki?::tree", :pairs, "tsuiseki?::critical_path", "tree then path")

edge(
  "tsuiseki?::carry",
  :pairs,
  "tsuiseki?::current",
  "carries the active span"
)

edge(
  "tsuiseki?::put",
  :pairs,
  "tsuiseki?::event",
  "attribute versus point event"
)

edge(
  "tsuiseki?::link",
  :refines,
  "tsuiseki?::put",
  "a relation stored on a span"
)

edge(
  "tsuiseki?::start",
  :requires,
  "tsuiseki?::adopt",
  "child of an adopted context"
)

edge(
  "tsuiseki?::adopt",
  :requires,
  "tsuiseki?::carry",
  "the sender wrote the carrier"
)

edge(
  "tsuiseki?::event",
  :requires,
  "tsuiseki?::current",
  "annotates the active span"
)

edge(
  "tsuiseki?::put",
  :requires,
  "tsuiseki?::current",
  "sets on the active span"
)

edge("tsuiseki?::current", :requires, "tsuiseki?::start", "a span must be open")

edge(
  "tsuiseki?::push",
  :requires,
  "tsuiseki?::stop",
  "only finished spans are sent"
)

edge(
  "tsuiseki?::critical_path",
  :requires,
  "tsuiseki?::tree",
  "walks the parent-child tree"
)

edge("tsuiseki?::diff", :requires, "tsuiseki?::tree", "compares two trees")
