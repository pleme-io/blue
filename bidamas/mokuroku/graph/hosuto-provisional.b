space("hosuto?", {status: :provisional})

verb(
  "hosuto?",
  "converge",
  {
    kind: :effect,
    shape: "converge(host, opts) -> outcome",
    laterals: %w[log process switch],
    fleet: "kirikae",
    today: "partial:kirikae",
    meaning: "bring a host to its declared system",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "drain",
  {
    kind: :effect,
    shape: "drain(host, opts) -> nil",
    laterals: %w[deadline idempotent switch],
    fleet: nil,
    today: "absent",
    meaning: "move work off a host",
    wave: 3,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "drift",
  {
    kind: :effect,
    shape: "drift(host) -> [difference]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declared system against the running one",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "facts",
  {
    kind: :effect,
    shape: "facts(host) -> record",
    laterals: %w[cache process],
    fleet: nil,
    today: "absent",
    meaning: "kernel, system, disk and load facts",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "get",
  {
    kind: :effect,
    shape: "get(name) -> host or nil",
    laterals: ["config"],
    fleet: "fleet",
    today: "absent",
    meaning: "one host record",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "group",
  {
    kind: :pure,
    shape: "group(hosts, key) -> record",
    laterals: [],
    fleet: "fleet",
    today: "absent",
    meaning: "hosts partitioned by role or site",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "health",
  {
    kind: :effect,
    shape: "health(host) -> verdict",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "healthy, degraded, down or blind",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [host]",
    laterals: ["config"],
    fleet: "fleet",
    today: "absent",
    meaning: "declared hosts and their groups",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "need",
  {
    kind: :effect,
    shape: "need(name) -> host",
    laterals: ["config"],
    fleet: "fleet",
    today: "absent",
    meaning: "one host, raises when absent",
    wave: 1,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "reach?",
  {
    kind: :effect,
    shape: "reach?(host, opts) -> Bool",
    laterals: %w[deadline process],
    fleet: "tehai",
    today: "partial:tehai",
    meaning: "whether the host answers now",
    wave: 0,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "wait",
  {
    kind: :effect,
    shape: "wait(host, state, opts) -> host",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "block until a host is up or gone",
    wave: 2,
    origin: "E"
  }
)

verb(
  "hosuto?",
  "wake",
  {
    kind: :effect,
    shape: "wake(host) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "bring a sleeping host up",
    wave: 3,
    origin: "E"
  }
)

edge("hosuto?::drift", :composes, "hosuto?::facts", "running versus declared")
edge("hosuto?::need", :composes, "hosuto?::get", "get then raise")
edge("hosuto?::get", :composes, "hosuto?::list", "lookup by name")
edge("hosuto?::group", :composes, "hosuto?::list", "partition the list")
edge("hosuto?::wait", :composes, "hosuto?::reach?", "poll until up")
edge("hosuto?::converge", :composes, "hyouka::copy", "closure sent first")
edge("hosuto?::health", :composes, "kenkou?::probe", "host verdict")
edge("hosuto?::converge", :composes, "kirikae::run", "switch the host")
edge("hosuto?::reach?", :composes, "tehai::probe", "builder probe generalised")
edge("hosuto?::drain", :guards, "hosuto?::converge", "move work before switch")
edge("hosuto?::wake", :inverse, "hosuto?::drain", "bring up versus empty")
edge("hosuto?::drain", :inverse, "hosuto?::wake", "bring up versus empty")
edge("hosuto?::facts", :pairs, "hosuto?::drift", "facts then compare")
edge("hosuto?::wake", :pairs, "hosuto?::wait", "wake then wait")
edge("hosuto?::get", :refines, "core::get", "nil when absent")
edge("hosuto?::group", :refines, "core::group_by", "partition hosts")
edge("hosuto?::facts", :refines, "core::info", "host state")
edge("hosuto?::list", :refines, "core::list", "declared hosts")
edge("hosuto?::need", :refines, "core::need", "raises when absent")
edge("hosuto?::health", :refines, "kenkou?::probe", "host as target")
edge("hosuto?::drift", :refines, "kouchiku?::drift", "same verb for hosts")
edge("hosuto?::converge", :requires, "hosuto?::reach?", "host must answer")
