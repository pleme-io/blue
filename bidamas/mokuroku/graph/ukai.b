space("ukai", {status: :ratified})

verb(
  "ukai",
  "apply",
  {
    kind: :effect,
    shape: "apply(plan, opts) -> record",
    laterals: %w[idempotent log process],
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
    laterals: %w[process resource],
    fleet: nil,
    today: "partial:ukai",
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
