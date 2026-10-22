space("kenkou?", {status: :provisional})

verb(
  "kenkou?",
  "budget",
  {
    kind: :pure,
    shape: "budget(slo, samples) -> {remaining:}",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "error budget left in a period",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kenkou?",
  "burn",
  {
    kind: :pure,
    shape: "burn(slo, samples, window) -> rate",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "how fast the budget is spent",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kenkou?",
  "gate",
  {
    kind: :pure,
    shape: "gate(verdicts, rule) -> verdict",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "combine probes into one go or no-go",
    wave: 2,
    origin: "E"
  }
)

verb(
  "kenkou?",
  "history",
  {
    kind: :effect,
    shape: "history(target, range) -> [verdict]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "past verdicts",
    wave: 3,
    origin: "E"
  }
)

verb(
  "kenkou?",
  "live?",
  {
    kind: :effect,
    shape: "live?(target) -> Bool",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "whether a target is running at all",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kenkou?",
  "probe",
  {
    kind: :effect,
    shape: "probe(target, check, opts) -> verdict",
    laterals: ["deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "healthy, degraded, down or blind, never guessed",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kenkou?",
  "ready?",
  {
    kind: :effect,
    shape: "ready?(target) -> Bool",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "whether a target takes traffic now",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kenkou?",
  "wait",
  {
    kind: :effect,
    shape: "wait(target, opts) -> verdict",
    laterals: ["cancel", "deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "block until a target is healthy",
    wave: 1,
    origin: "E"
  }
)

edge("kenkou?::burn", :composes, "kenkou?::budget", "rate of spend")
edge("kenkou?::gate", :composes, "kenkou?::probe", "combine verdicts")
edge("kenkou?::live?", :composes, "kenkou?::probe", "predicate form")
edge("kenkou?::ready?", :composes, "kenkou?::probe", "predicate form")
edge("kenkou?::wait", :composes, "kenkou?::probe", "poll until healthy")
edge("kenkou?::wait", :composes, "kenkou?::ready?", "poll until ready")
edge("kenkou?::gate", :guards, "tenkai?::step", "health gates rollout")
edge("kenkou?::live?", :pairs, "kenkou?::ready?", "liveness and readiness")
edge("kenkou?::probe", :pairs, "kenkou?::ready?", "probe and its predicate")
edge("kenkou?::probe", :pairs, "kurasuta::wait", "cluster condition is a probe")
edge("kenkou?::probe", :refines, "core::info", "state with blind kept")
edge("kenkou?::history", :refines, "core::list", "past verdicts")
edge("kenkou?::budget", :requires, "kenkou?::history", "samples over a period")
