space("furagu?", {status: :provisional})

verb(
  "furagu?",
  "eval",
  {
    kind: :effect,
    shape: "eval(flag, context) -> value",
    laterals: %w[cache config],
    fleet: nil,
    today: "absent",
    meaning: "the value of a flag for a context",
    wave: 3,
    origin: "E"
  }
)

verb(
  "furagu?",
  "history",
  {
    kind: :effect,
    shape: "history(flag) -> [change]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "who changed a flag and when",
    wave: 4,
    origin: "E"
  }
)

verb(
  "furagu?",
  "kill",
  {
    kind: :effect,
    shape: "kill(flag, reason) -> flag",
    laterals: %w[idempotent log switch],
    fleet: nil,
    today: "absent",
    meaning: "turn a flag off for everyone at once",
    wave: 3,
    origin: "E"
  }
)

verb(
  "furagu?",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [flag]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "every flag with its rule",
    wave: 3,
    origin: "E"
  }
)

verb(
  "furagu?",
  "on?",
  {
    kind: :effect,
    shape: "on?(flag, context) -> Bool",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "whether a boolean flag is on",
    wave: 3,
    origin: "E"
  }
)

verb(
  "furagu?",
  "put",
  {
    kind: :effect,
    shape: "put(flag, rule, opts) -> flag",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "create or replace a flag rule",
    wave: 3,
    origin: "E"
  }
)

verb(
  "furagu?",
  "ramp",
  {
    kind: :effect,
    shape: "ramp(flag, percent) -> flag",
    laterals: %w[log switch],
    fleet: nil,
    today: "absent",
    meaning: "raise the share of contexts that see it",
    wave: 3,
    origin: "E"
  }
)

verb(
  "furagu?",
  "stale?",
  {
    kind: :effect,
    shape: "stale?(flag, opts) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether a flag changed nothing for a long time",
    wave: 4,
    origin: "E",
    contract: "stale?(flag) -> Bool"
  }
)

verb(
  "furagu?",
  "watch",
  {
    kind: :stream,
    shape: "watch(flag, f) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "call f when a flag's rule changes",
    wave: 4,
    origin: "E"
  }
)

edge("furagu?::on?", :composes, "furagu?::eval", "boolean form")
edge("furagu?::put", :composes, "furagu?::history", "each put leaves a change")
edge("furagu?::stale?", :composes, "furagu?::history", "age of last change")
edge("furagu?::ramp", :inverse, "furagu?::kill", "off versus up")
edge("furagu?::kill", :inverse, "furagu?::ramp", "off versus up")
edge("furagu?::watch", :lifts, "furagu?::eval", "rule change stream")
edge("furagu?::eval", :pairs, "furagu?::on?", "value versus boolean")
edge("furagu?::kill", :pairs, "tenkai?::rollback", "fast off without redeploy")

edge(
  "furagu?::ramp",
  :pairs,
  "tenkai?::shift",
  "flag ramp mirrors traffic shift"
)

edge("furagu?::eval", :refines, "core::get", "flag value")
edge("furagu?::history", :refines, "core::list", "changes")
edge("furagu?::list", :refines, "core::list", "flags")
edge("furagu?::put", :refines, "core::put", "flag rule")
edge("furagu?::kill", :refines, "furagu?::put", "rule off")
edge("furagu?::ramp", :refines, "furagu?::put", "percent rule")
