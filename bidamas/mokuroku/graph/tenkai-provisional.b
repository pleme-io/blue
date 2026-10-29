space("tenkai?", {status: :provisional})

verb(
  "tenkai?",
  "abort",
  {
    kind: :effect,
    shape: "abort(rollout, reason) -> rollout",
    laterals: %w[cancel idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "stop and keep the current mix",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "analyze",
  {
    kind: :effect,
    shape: "analyze(rollout, window) -> verdict",
    laterals: %w[time validate],
    fleet: nil,
    today: "absent",
    meaning: "compare new against old on live metrics",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "approve",
  {
    kind: :effect,
    shape: "approve(rollout, gate, opts) -> nil",
    laterals: %w[capability log],
    fleet: nil,
    today: "absent",
    meaning: "let a held gate pass, naming who",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "bake",
  {
    kind: :effect,
    shape: "bake(rollout, duration) -> verdict",
    laterals: %w[cancel deadline time],
    fleet: nil,
    today: "absent",
    meaning: "hold a stage for a soak period",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "freeze",
  {
    kind: :effect,
    shape: "freeze(scope, reason, opts) -> window",
    laterals: %w[capability log time],
    fleet: nil,
    today: "absent",
    meaning: "forbid rollouts in a scope for a time",
    wave: 3,
    origin: "E",
    contract: "freeze(scope, reason) -> window"
  }
)

verb(
  "tenkai?",
  "info",
  {
    kind: :effect,
    shape: "info(rollout) -> record",
    laterals: ["error"],
    fleet: "forge",
    today: "absent",
    meaning: "step, weight, health and age",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [rollout]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "rollouts, newest first",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "pause",
  {
    kind: :effect,
    shape: "pause(rollout) -> rollout",
    laterals: %w[idempotent switch],
    fleet: nil,
    today: "absent",
    meaning: "hold a rollout where it stands",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "plan",
  {
    kind: :pure,
    shape: "plan(strategy, from, to) -> [step]",
    laterals: ["validate"],
    fleet: "forge",
    today: "absent",
    meaning: "steps a rollout would take, as data",
    wave: 1,
    origin: "E",
    contract: "plan(strategy, from, opts) -> [step]"
  }
)

verb(
  "tenkai?",
  "promote",
  {
    kind: :effect,
    shape: "promote(rollout) -> rollout",
    laterals: %w[log switch],
    fleet: nil,
    today: "absent",
    meaning: "make the new version the only one",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "resume",
  {
    kind: :effect,
    shape: "resume(rollout) -> rollout",
    laterals: %w[idempotent switch],
    fleet: nil,
    today: "absent",
    meaning: "continue a held rollout",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "rollback",
  {
    kind: :effect,
    shape: "rollback(rollout, {to:}) -> rollout",
    laterals: %w[idempotent log switch],
    fleet: nil,
    today: "absent",
    meaning: "return all traffic to the earlier version",
    wave: 2,
    origin: "E",
    contract: "rollback(rollout, opts) -> rollout"
  }
)

verb(
  "tenkai?",
  "shift",
  {
    kind: :effect,
    shape: "shift(rollout, weight) -> rollout",
    laterals: %w[log switch],
    fleet: nil,
    today: "absent",
    meaning: "move a share of traffic to the new version",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "start",
  {
    kind: :effect,
    shape: "start(plan, opts) -> rollout",
    laterals: %w[capability idempotent log],
    fleet: "forge",
    today: "absent",
    meaning: "begin a rollout",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "step",
  {
    kind: :effect,
    shape: "step(rollout) -> rollout",
    laterals: %w[log switch],
    fleet: nil,
    today: "absent",
    meaning: "advance one stage",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "thaw",
  {
    kind: :effect,
    shape: "thaw(window) -> nil",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "end a change freeze",
    wave: 3,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "verify",
  {
    kind: :effect,
    shape: "verify(rollout) -> verdict",
    laterals: %w[deadline validate],
    fleet: "forge",
    today: "absent",
    meaning: "health gate before the next step",
    wave: 2,
    origin: "E"
  }
)

verb(
  "tenkai?",
  "watch",
  {
    kind: :stream,
    shape: "watch(rollout, f, opts) -> nil",
    laterals: %w[cancel deadline],
    fleet: "shinchoku",
    today: "absent",
    meaning: "call f per step or health change",
    wave: 2,
    origin: "E"
  }
)

edge("tenkai?::verify", :composes, "kenkou?::gate", "health gate")
edge("tenkai?::analyze", :composes, "kenkou?::probe", "live signals")
edge("tenkai?::bake", :composes, "kenkou?::wait", "soak is a timed wait")
edge("tenkai?::list", :composes, "tenkai?::info", "each rollout's state")
edge("tenkai?::start", :composes, "tenkai?::plan", "plan then begin")
edge("tenkai?::rollback", :composes, "tenkai?::shift", "weight back to old")
edge("tenkai?::step", :composes, "tenkai?::shift", "weight moves per step")
edge("tenkai?::promote", :composes, "tenkai?::step", "final step")
edge("tenkai?::bake", :composes, "tenkai?::verify", "verify over a period")
edge("tenkai?::step", :composes, "tenkai?::verify", "verify then advance")

edge(
  "tenkai?::rollback",
  :guards,
  "tenkai?::promote",
  "rollback path ready first"
)

edge("tenkai?::pause", :guards, "tenkai?::step", "held rollouts do not step")
edge("tenkai?::verify", :guards, "tenkai?::step", "gate before advance")
edge("tenkai?::thaw", :inverse, "tenkai?::freeze", "open versus close window")
edge("tenkai?::resume", :inverse, "tenkai?::pause", "hold versus continue")
edge("tenkai?::rollback", :inverse, "tenkai?::promote", "undo the move")
edge("tenkai?::pause", :inverse, "tenkai?::resume", "hold versus continue")
edge("tenkai?::promote", :inverse, "tenkai?::rollback", "undo the move")
edge("tenkai?::freeze", :inverse, "tenkai?::thaw", "open versus close window")
edge("tenkai?::watch", :lifts, "tenkai?::info", "stream of state")
edge("tenkai?::start", :pairs, "tenkai?::abort", "begin and end")
edge("tenkai?::promote", :pairs, "uwagaki?::promote", "app and environment")
edge("tenkai?::info", :refines, "core::info", "rollout state")
edge("tenkai?::list", :refines, "core::list", "rollouts")
edge("tenkai?::plan", :refines, "core::plan", "steps as data")
edge("tenkai?::approve", :refines, "paipurain?::approve", "same gate verb")
edge("tenkai?::abort", :refines, "tenkai?::pause", "hold and end")
edge("tenkai?::shift", :refines, "tenkai?::step", "step by traffic weight")
edge("tenkai?::analyze", :refines, "tenkai?::verify", "canary comparison")
edge("tenkai?::start", :requires, "tenkai?::freeze", "no start inside a freeze")
edge("tenkai?::thaw", :requires, "tenkai?::freeze", "ends a window")
edge("tenkai?::resume", :requires, "tenkai?::pause", "only a held rollout")
edge("tenkai?::plan", :requires, "uwagaki?::resolve", "environment config")
