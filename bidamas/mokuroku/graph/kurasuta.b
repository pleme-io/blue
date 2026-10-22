space("kurasuta", {status: :ratified})

verb(
  "kurasuta",
  "can?",
  {
    kind: :effect,
    shape: "can?(verb, kind, opts) -> Bool",
    laterals: ["capability"],
    fleet: "banken",
    today: "absent",
    meaning: "whether the credential may do that",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "describe",
  {
    kind: :pure,
    shape: "describe(kind) -> schema",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "fields a kind accepts",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "diff",
  {
    kind: :effect,
    shape: "diff(desired, opts) -> [change]",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "live objects against rendered manifests",
    wave: 1,
    origin: "E",
    contract: "diff(desired, b, opts) -> [change]"
  }
)

verb(
  "kurasuta",
  "events",
  {
    kind: :effect,
    shape: "events(subject, opts) -> [event]",
    laterals: ["time"],
    fleet: "banken",
    today: "absent",
    meaning: "cluster events about one object",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "get",
  {
    kind: :effect,
    shape: "get(kind, name, opts) -> object or nil",
    laterals: ["error"],
    fleet: "banken",
    today: "absent",
    meaning: "one object, nil when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "has?",
  {
    kind: :effect,
    shape: "has?(kind, name, opts) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether an object exists",
    wave: 1,
    origin: "E",
    contract: "has?(kind, name) -> Bool"
  }
)

verb(
  "kurasuta",
  "info",
  {
    kind: :effect,
    shape: "info(opts) -> record",
    laterals: ["error"],
    fleet: "banken",
    today: "absent",
    meaning: "cluster version and reachability",
    wave: 1,
    origin: "E",
    contract: "info(subject, opts) -> record"
  }
)

verb(
  "kurasuta",
  "list",
  {
    kind: :effect,
    shape: "list(kind, opts) -> [object]",
    laterals: ["deadline", "error"],
    fleet: "banken",
    today: "absent",
    meaning: "every object of a kind, all pages, sorted",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "need",
  {
    kind: :effect,
    shape: "need(kind, name, opts) -> object",
    laterals: ["error"],
    fleet: "banken",
    today: "absent",
    meaning: "one object, raises when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "read",
  {
    kind: :effect,
    shape: "read(pod, opts) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "container logs",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "render",
  {
    kind: :pure,
    shape: "render(chart, values) -> [object]",
    laterals: ["serialize", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "objects a chart yields, no cluster contact",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "top",
  {
    kind: :effect,
    shape: "top(kind, opts) -> [usage]",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "cpu and memory in use",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kurasuta",
  "wait",
  {
    kind: :effect,
    shape: "wait(kind, name, condition, opts) -> object",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "block until a condition holds",
    wave: 1,
    origin: "E",
    contract: "wait(kind, name, opts) -> object"
  }
)

verb(
  "kurasuta",
  "watch",
  {
    kind: :stream,
    shape: "watch(kind, f, opts) -> nil",
    laterals: ["cancel", "deadline"],
    fleet: "banken",
    today: "absent",
    meaning: "call f per change until it returns stop",
    wave: 1,
    origin: "E"
  }
)

edge("kurasuta::diff", :composes, "kurasuta::get", "compare with live")
edge("kurasuta::need", :composes, "kurasuta::get", "get then raise")
edge("kurasuta::watch", :composes, "kurasuta::get", "keyed by object")
edge("kurasuta::diff", :composes, "kurasuta::render", "render desired first")
edge("kurasuta::wait", :composes, "kurasuta::watch", "watch until condition")
edge("kurasuta::info", :guards, "kurasuta::list", "reachable cluster first")
edge("kurasuta::can?", :guards, "kurasuta::read", "check access first")
edge("kurasuta::watch", :lifts, "kurasuta::list", "stream of changes")

edge(
  "kurasuta::diff",
  :pairs,
  "kouchiku?::drift",
  "same compare in cluster scope"
)

edge("kurasuta::read", :pairs, "kurasuta::events", "logs and events")

edge(
  "kurasuta::describe",
  :pairs,
  "kurasuta::render",
  "schema explains manifests"
)

edge("kurasuta::top", :pairs, "youryou?::observe", "usage feeds bands")
edge("kurasuta::get", :refines, "core::get", "nil when absent")
edge("kurasuta::has?", :refines, "core::has?", "object present")
edge("kurasuta::info", :refines, "core::info", "cluster state")
edge("kurasuta::list", :refines, "core::list", "objects of a kind")
edge("kurasuta::need", :refines, "core::need", "raises when absent")
edge("kurasuta::read", :refines, "core::read", "pod logs")
edge("kurasuta::render", :refines, "core::render", "chart to objects")
edge("kurasuta::events", :refines, "kurasuta::list", "events are objects")
edge("kurasuta::top", :refines, "kurasuta::list", "usage metrics")
