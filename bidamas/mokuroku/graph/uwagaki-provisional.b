space("uwagaki?", {status: :provisional})

verb(
  "uwagaki?",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> [change]",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "how two environments differ in resolved config",
    wave: 1,
    origin: "E"
  }
)

verb(
  "uwagaki?",
  "freeze",
  {
    kind: :effect,
    shape: "freeze(name, reason) -> nil",
    laterals: %w[capability idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "stop changes to an environment",
    wave: 3,
    origin: "E"
  }
)

verb(
  "uwagaki?",
  "get",
  {
    kind: :effect,
    shape: "get(name) -> environment or nil",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "one environment's record",
    wave: 1,
    origin: "E"
  }
)

verb(
  "uwagaki?",
  "list",
  {
    kind: :effect,
    shape: "list() -> [environment]",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "named deploy targets",
    wave: 1,
    origin: "E"
  }
)

verb(
  "uwagaki?",
  "need",
  {
    kind: :effect,
    shape: "need(name) -> environment",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "one environment, raises when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "uwagaki?",
  "path",
  {
    kind: :pure,
    shape: "path(name) -> [environment]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "environments a change passes through in order",
    wave: 2,
    origin: "E",
    contract: "path(name, from, to, opts) -> [environment]"
  }
)

verb(
  "uwagaki?",
  "promote",
  {
    kind: :effect,
    shape: "promote(change, from, to) -> change",
    laterals: %w[log switch],
    fleet: nil,
    today: "absent",
    meaning: "carry a pinned change to the next environment",
    wave: 2,
    origin: "E",
    contract: "promote(change, from, opts) -> change"
  }
)

verb(
  "uwagaki?",
  "resolve",
  {
    kind: :pure,
    shape: "resolve(spec, environment) -> record",
    laterals: %w[config validate],
    fleet: nil,
    today: "absent",
    meaning: "a spec with this environment's overlay applied",
    wave: 1,
    origin: "E"
  }
)

edge("uwagaki?::resolve", :composes, "settei::read", "layered config")
edge("uwagaki?::need", :composes, "uwagaki?::get", "get then raise")
edge("uwagaki?::get", :composes, "uwagaki?::list", "lookup by name")
edge("uwagaki?::path", :composes, "uwagaki?::list", "ordered list")
edge("uwagaki?::diff", :composes, "uwagaki?::resolve", "resolve both sides")
edge("uwagaki?::freeze", :guards, "tenkai?::freeze", "environment-wide freeze")
edge("uwagaki?::promote", :guards, "tenkai?::start", "pin carried forward")
edge("uwagaki?::promote", :inverse, "uwagaki?::freeze", "freezes versus moves")
edge("uwagaki?::freeze", :inverse, "uwagaki?::promote", "freezes versus moves")
edge("uwagaki?::resolve", :pairs, "uwagaki?::diff", "compare resolved records")
edge("uwagaki?::diff", :refines, "core::diff", "between environments")
edge("uwagaki?::get", :refines, "core::get", "nil when absent")
edge("uwagaki?::list", :refines, "core::list", "environments")
edge("uwagaki?::need", :refines, "core::need", "raises when absent")
edge("uwagaki?::resolve", :requires, "uwagaki?::need", "environment must exist")
edge("uwagaki?::promote", :requires, "uwagaki?::path", "next environment")
