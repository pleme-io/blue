space("keikaku?", {status: :provisional})

verb(
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
  "checkin",
  {
    kind: :effect,
    shape: "checkin(goal, progress) -> nil",
    laterals: ["log", "time"],
    fleet: nil,
    today: "absent",
    meaning: "record progress against a goal",
    wave: 3,
    origin: "F"
  }
)

verb(
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
  "goal",
  {
    kind: :decl,
    shape: "goal(owner, target, window) -> goal",
    laterals: ["config", "time"],
    fleet: nil,
    today: "absent",
    meaning: "declare an outcome target for a person or team",
    wave: 3,
    origin: "F"
  }
)

verb(
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
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
  "keikaku?",
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

edge("keikaku?::schedule", :composes, "keikaku?::estimate", "uses sizes")

edge(
  "keikaku?::roadmap",
  :composes,
  "keikaku?::milestone",
  "ordered milestones"
)

edge(
  "keikaku?::variance",
  :composes,
  "keikaku?::schedule",
  "plan against actual"
)

edge(
  "keikaku?::forecast",
  :composes,
  "keikaku?::velocity",
  "backlog over velocity"
)

edge("keikaku?::checkin", :composes, "nisshi::append", "progress is an event")

edge(
  "keikaku?::estimate",
  :pairs,
  "kadai?::update",
  "sizes are stored on issues"
)

edge(
  "keikaku?::sprint",
  :pairs,
  "keikaku?::burndown",
  "a sprint is burned down"
)

edge("keikaku?::goal", :pairs, "keikaku?::checkin", "target and progress")
edge("keikaku?::schedule", :pairs, "keikaku?::critical_path", "order and chain")
edge("keikaku?::milestone", :pairs, "keikaku?::roadmap", "dated sets")

edge(
  "keikaku?::capacity",
  :pairs,
  "keikaku?::schedule",
  "places items by capacity"
)

edge(
  "keikaku?::forecast",
  :pairs,
  "keikaku?::variance",
  "forecast then compare"
)

edge("keikaku?::risk", :pairs, "keikaku?::variance", "risk turns into variance")
edge("keikaku?::estimate", :pairs, "keikaku?::velocity", "size over speed")

edge(
  "keikaku?::goal",
  :pairs,
  "shihyou::objective",
  "goals are objectives for people"
)

edge(
  "keikaku?::velocity",
  :pairs,
  "shihyou::throughput",
  "history versus metric"
)

edge(
  "keikaku?::risk",
  :pairs,
  "shougai?::classify",
  "a risk met is an incident"
)

edge(
  "keikaku?::capacity",
  :pairs,
  "shougai?::oncall",
  "on-call reduces capacity"
)

edge(
  "keikaku?::retro",
  :pairs,
  "shougai?::postmortem",
  "retro covers a period, postmortem an event"
)

edge("keikaku?::sprint", :refines, "keikaku?::milestone", "time-boxed")

edge(
  "keikaku?::critical_path",
  :refines,
  "tsuiseki?::critical_path",
  "same law on a task graph"
)

edge("keikaku?::milestone", :requires, "kadai?::list", "a set of issues")
edge("keikaku?::velocity", :requires, "kadai?::list", "from finished issues")

edge(
  "keikaku?::burndown",
  :requires,
  "keikaku?::sprint",
  "work left in a sprint"
)

edge("keikaku?::retro", :requires, "nisshi::read", "facts from events")
