space("puran?", {status: :provisional})

verb(
  "puran?",
  "burndown",
  {
    kind: :pure,
    shape: "burndown(items, window) -> series",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "work left over time",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "capacity",
  {
    kind: :pure,
    shape: "capacity(team, window) -> number",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "work a team can take on in a window",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "checkin",
  {
    kind: :effect,
    shape: "checkin(goal, progress) -> nil",
    laterals: %w[log time],
    fleet: nil,
    today: "absent",
    meaning: "record progress against a goal",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "critical_path",
  {
    kind: :pure,
    shape: "critical_path(items) -> [item]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "the chain of dependent items that sets the end date",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "estimate",
  {
    kind: :pure,
    shape: "estimate(item, method) -> estimate",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a size or duration for an item, with its range",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "forecast",
  {
    kind: :pure,
    shape: "forecast(backlog, velocity, opts) -> distribution",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "when a backlog finishes, as dates with odds",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "goal",
  {
    kind: :decl,
    shape: "goal(owner, target, window) -> goal",
    laterals: %w[config time],
    fleet: nil,
    today: "absent",
    meaning: "declare an outcome target for a person or team",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "milestone",
  {
    kind: :decl,
    shape: "milestone(name, due, items) -> milestone",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "declare a dated set of items",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "retro",
  {
    kind: :pure,
    shape: "retro(events, window) -> record",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "facts from a period: what changed, slipped and repeated",
    wave: 4,
    origin: "F"
  }
)

verb(
  "puran?",
  "risk",
  {
    kind: :decl,
    shape: "risk(name, odds, impact) -> risk",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "declare something that may go wrong, with odds and cost",
    wave: 4,
    origin: "F"
  }
)

verb(
  "puran?",
  "roadmap",
  {
    kind: :pure,
    shape: "roadmap(milestones) -> roadmap",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "milestones in time order, by theme",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "schedule",
  {
    kind: :pure,
    shape: "schedule(items, capacity) -> plan",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "items placed in periods by order, size and capacity",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "sprint",
  {
    kind: :decl,
    shape: "sprint(window, items) -> sprint",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "declare a time-boxed set of items",
    wave: 3,
    origin: "F"
  }
)

verb(
  "puran?",
  "variance",
  {
    kind: :pure,
    shape: "variance(plan, actual) -> record",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "how far reality moved from the plan",
    wave: 3,
    origin: "F",
    contract: "variance(plan, opts) -> record"
  }
)

verb(
  "puran?",
  "velocity",
  {
    kind: :pure,
    shape: "velocity(history, window) -> distribution",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "work finished per period, as a distribution",
    wave: 3,
    origin: "F"
  }
)

edge("puran?::checkin", :composes, "nisshi::append", "progress is an event")
edge("puran?::schedule", :composes, "puran?::estimate", "uses sizes")
edge("puran?::roadmap", :composes, "puran?::milestone", "ordered milestones")
edge("puran?::variance", :composes, "puran?::schedule", "plan against actual")
edge("puran?::forecast", :composes, "puran?::velocity", "backlog over velocity")
edge("puran?::estimate", :pairs, "kadai?::update", "sizes are stored on issues")
edge("puran?::sprint", :pairs, "puran?::burndown", "a sprint is burned down")
edge("puran?::goal", :pairs, "puran?::checkin", "target and progress")
edge("puran?::schedule", :pairs, "puran?::critical_path", "order and chain")
edge("puran?::milestone", :pairs, "puran?::roadmap", "dated sets")
edge("puran?::capacity", :pairs, "puran?::schedule", "places items by capacity")
edge("puran?::forecast", :pairs, "puran?::variance", "forecast then compare")
edge("puran?::risk", :pairs, "puran?::variance", "risk turns into variance")
edge("puran?::estimate", :pairs, "puran?::velocity", "size over speed")

edge(
  "puran?::goal",
  :pairs,
  "shihyou::objective",
  "goals are objectives for people"
)

edge("puran?::velocity", :pairs, "shihyou::throughput", "history versus metric")
edge("puran?::risk", :pairs, "shougai?::classify", "a risk met is an incident")
edge("puran?::capacity", :pairs, "shougai?::oncall", "on-call reduces capacity")

edge(
  "puran?::retro",
  :pairs,
  "shougai?::postmortem",
  "retro covers a period, postmortem an event"
)

edge("puran?::sprint", :refines, "puran?::milestone", "time-boxed")

edge(
  "puran?::critical_path",
  :refines,
  "tsuiseki?::critical_path",
  "same law on a task graph"
)

edge("puran?::milestone", :requires, "kadai?::list", "a set of issues")
edge("puran?::velocity", :requires, "kadai?::list", "from finished issues")
edge("puran?::retro", :requires, "nisshi::read", "facts from events")
edge("puran?::burndown", :requires, "puran?::sprint", "work left in a sprint")
