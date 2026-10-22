space("haichi?", {status: :provisional})

verb(
  "haichi?",
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
  "haichi?",
  "freeze",
  {
    kind: :effect,
    shape: "freeze(name, reason) -> nil",
    laterals: ["capability", "idempotent", "log"],
    fleet: nil,
    today: "absent",
    meaning: "stop changes to an environment",
    wave: 3,
    origin: "E"
  }
)

verb(
  "haichi?",
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
  "haichi?",
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
  "haichi?",
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
  "haichi?",
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
  "haichi?",
  "promote",
  {
    kind: :effect,
    shape: "promote(change, from, to) -> change",
    laterals: ["log", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "carry a pinned change to the next environment",
    wave: 2,
    origin: "E",
    contract: "promote(change, from, opts) -> change"
  }
)

verb(
  "haichi?",
  "resolve",
  {
    kind: :pure,
    shape: "resolve(spec, environment) -> record",
    laterals: ["config", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "a spec with this environment's overlay applied",
    wave: 1,
    origin: "E"
  }
)

edge("haichi?::need", :composes, "haichi?::get", "get then raise")
edge("haichi?::get", :composes, "haichi?::list", "lookup by name")
edge("haichi?::path", :composes, "haichi?::list", "ordered list")
edge("haichi?::diff", :composes, "haichi?::resolve", "resolve both sides")
edge("haichi?::resolve", :composes, "settei::read", "layered config")
edge("haichi?::freeze", :guards, "tenkai?::freeze", "environment-wide freeze")
edge("haichi?::promote", :guards, "tenkai?::start", "pin carried forward")
edge("haichi?::promote", :inverse, "haichi?::freeze", "freezes versus moves")
edge("haichi?::freeze", :inverse, "haichi?::promote", "freezes versus moves")
edge("haichi?::resolve", :pairs, "haichi?::diff", "compare resolved records")
edge("haichi?::diff", :refines, "core::diff", "between environments")
edge("haichi?::get", :refines, "core::get", "nil when absent")
edge("haichi?::list", :refines, "core::list", "environments")
edge("haichi?::need", :refines, "core::need", "raises when absent")
edge("haichi?::resolve", :requires, "haichi?::need", "environment must exist")
edge("haichi?::promote", :requires, "haichi?::path", "next environment")
