space("ukai", {status: :ratified})

verb(
  "ukai",
  "apply",
  {
    kind: :effect,
    shape: "apply(plan, opts) -> record",
    laterals: ["idempotent", "log", "process"],
    fleet: nil,
    today: "partial:ukai",
    meaning: "install the planned routes; same plan twice changes nothing",
    wave: 1,
    origin: "D"
  }
)

verb(
  "ukai",
  "decide",
  {
    kind: :pure,
    shape: "decide(state) -> outcome",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:ukai",
    meaning: "noop, bypass, refused or blind, over a total state",
    wave: 0,
    origin: "D"
  }
)

verb(
  "ukai",
  "observe",
  {
    kind: :effect,
    shape: "observe(opts) -> state",
    laterals: ["process", "resource"],
    fleet: nil,
    today: "partial:ukai",
    meaning: "read routes and overlay status into one typed state",
    wave: 0,
    origin: "D"
  }
)

verb(
  "ukai",
  "plan",
  {
    kind: :pure,
    shape: "plan(outcome) -> [action]",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:ukai",
    meaning: "host routes or policy rules an outcome needs",
    wave: 0,
    origin: "D"
  }
)

edge("ukai::observe", :pairs, "ukai::decide", "observed then decided")
edge("ukai::apply", :pairs, "ukai::plan", "plan describes, apply does")

edge(
  "ukai::apply",
  :requires,
  "shisutemu::run",
  "installs routes through a process"
)

edge(
  "ukai::observe",
  :requires,
  "shisutemu::run",
  "reads routes through a process"
)

edge("ukai::plan", :requires, "ukai::decide", "actions from an outcome")
edge("ukai::decide", :requires, "ukai::observe", "decides over observed state")
edge("ukai::apply", :requires, "ukai::plan", "installs a plan")
