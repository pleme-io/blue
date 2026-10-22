space("joujuu", {status: :ratified})

verb(
  "joujuu",
  "active?",
  {
    kind: :effect,
    shape: "active?(unit) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether a unit is running now",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "enabled?",
  {
    kind: :effect,
    shape: "enabled?(unit) -> Bool",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "whether a unit starts at boot or login",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "info",
  {
    kind: :effect,
    shape: "info(unit) -> record",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "state, pid, last exit, since",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "limits",
  {
    kind: :effect,
    shape: "limits(unit) -> record",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "memory, cpu and file limits in force",
    wave: 2,
    origin: "E"
  }
)

verb(
  "joujuu",
  "list",
  {
    kind: :effect,
    shape: "list(opts) -> [unit]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "every service with state",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "plan",
  {
    kind: :pure,
    shape: "plan(action, units) -> [action]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "what a restart would touch",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "read",
  {
    kind: :effect,
    shape: "read(unit, {since:}) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "journal or launchd log",
    wave: 1,
    origin: "E",
    contract: "read(unit, opts) -> text"
  }
)

verb(
  "joujuu",
  "reload",
  {
    kind: :effect,
    shape: "reload(unit) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "re-read configuration without ending the process",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "reset",
  {
    kind: :effect,
    shape: "reset(unit) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "clear a failed state",
    wave: 2,
    origin: "E"
  }
)

verb(
  "joujuu",
  "restart",
  {
    kind: :effect,
    shape: "restart(unit, opts) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "stop then start",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "signal",
  {
    kind: :effect,
    shape: "signal(unit, sig) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "send a signal to a unit's processes",
    wave: 2,
    origin: "E"
  }
)

verb(
  "joujuu",
  "start",
  {
    kind: :effect,
    shape: "start(unit, opts) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "start a service",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "stop",
  {
    kind: :effect,
    shape: "stop(unit, opts) -> nil",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "end a service after a grace period",
    wave: 1,
    origin: "E"
  }
)

verb(
  "joujuu",
  "wait",
  {
    kind: :effect,
    shape: "wait(unit, state, opts) -> record",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "block until a unit reaches a state",
    wave: 1,
    origin: "E"
  }
)

edge("joujuu::active?", :composes, "joujuu::info", "state is active")
edge("joujuu::enabled?", :composes, "joujuu::info", "boot setting")
edge("joujuu::limits", :composes, "joujuu::info", "part of unit state")
edge("joujuu::wait", :composes, "joujuu::info", "poll state")
edge("joujuu::stop", :composes, "joujuu::signal", "term then kill")
edge("joujuu::restart", :composes, "joujuu::start", "stop then start")
edge("joujuu::restart", :composes, "joujuu::stop", "stop then start")
edge("joujuu::start", :composes, "joujuu::wait", "start then wait active")
edge("joujuu::reset", :guards, "joujuu::start", "clear failed state first")
edge("joujuu::stop", :inverse, "joujuu::start", "begin versus end")
edge("joujuu::start", :inverse, "joujuu::stop", "begin versus end")
edge("joujuu::plan", :pairs, "joujuu::restart", "preview then act")
edge("joujuu::wait", :pairs, "kenkou?::wait", "unit state is a probe")
edge("joujuu::info", :refines, "core::info", "unit state")
edge("joujuu::list", :refines, "core::list", "units")
edge("joujuu::plan", :refines, "core::plan", "what restart touches")
edge("joujuu::read", :refines, "core::read", "journal")
edge("joujuu::reload", :refines, "joujuu::restart", "no process end")
edge("joujuu::signal", :refines, "joujuu::stop", "stop is a signal")
