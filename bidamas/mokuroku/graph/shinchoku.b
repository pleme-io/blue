space("shinchoku", {status: :ratified})

verb(
  "shinchoku",
  "info",
  {
    kind: :effect,
    shape: "info(target) -> record",
    laterals: ["error"],
    fleet: "shinchoku",
    today: "partial:shinchoku",
    meaning: "generation, observed generation and phase",
    wave: 1,
    origin: "E"
  }
)

verb(
  "shinchoku",
  "progress",
  {
    kind: :pure,
    shape: "progress(samples, window) -> verdict",
    laterals: ["time"],
    fleet: "shinchoku",
    today: "exists:shinchoku",
    meaning: "moving, stalled or blind from counter samples",
    wave: 0,
    origin: "E"
  }
)

verb(
  "shinchoku",
  "watch",
  {
    kind: :stream,
    shape: "watch(target, f, opts) -> nil",
    laterals: ["cancel", "time"],
    fleet: "shinchoku",
    today: "partial:shinchoku",
    meaning: "sample a reconciler until it settles or stalls",
    wave: 1,
    origin: "E"
  }
)

edge("shinchoku::watch", :lifts, "shinchoku::progress", "sample repeatedly")
edge("shinchoku::info", :pairs, "shinchoku::progress", "generation then motion")

edge(
  "shinchoku::watch",
  :pairs,
  "tenkai?::watch",
  "reconciler progress for rollouts"
)

edge("shinchoku::progress", :refines, "core::info", "verdict from samples")
edge("shinchoku::info", :refines, "kurasuta::get", "reads generation fields")
