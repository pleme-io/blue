space("kirikae", {status: :ratified})

verb(
  "kirikae",
  "decide",
  {
    kind: :pure,
    shape: "decide(desired, current, history, now, policy) -> verdict",
    laterals: ["retry", "switch"],
    fleet: "kirikae",
    today: "exists:kirikae",
    meaning: "switch, hold or no-op from state and backoff",
    wave: 0,
    origin: "E",
    contract: "decide(desired, current, history, now) -> verdict"
  }
)

verb(
  "kirikae",
  "hold",
  {
    kind: :pure,
    shape: "hold(key, history, now, policy) -> record or nil",
    laterals: ["retry", "time"],
    fleet: "kirikae",
    today: "partial:kirikae",
    meaning: "back-off window after repeated failure",
    wave: 0,
    origin: "E"
  }
)

verb(
  "kirikae",
  "list",
  {
    kind: :effect,
    shape: "list(host, opts) -> [generation]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "generations a host can roll back to",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kirikae",
  "plan",
  {
    kind: :pure,
    shape: "plan(flake, host, opts) -> action",
    laterals: ["error", "validate"],
    fleet: "kirikae",
    today: "exists:kirikae",
    meaning: "what a system switch would do, as data",
    wave: 0,
    origin: "E"
  }
)

verb(
  "kirikae",
  "record",
  {
    kind: :effect,
    shape: "record(path, entry) -> nil",
    laterals: ["idempotent", "serialize"],
    fleet: "kirikae",
    today: "exists:kirikae",
    meaning: "append one outcome to the switch history",
    wave: 0,
    origin: "E"
  }
)

verb(
  "kirikae",
  "rollback",
  {
    kind: :effect,
    shape: "rollback(host, {to:}) -> outcome",
    laterals: ["error", "process", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "activate an earlier generation",
    wave: 1,
    origin: "E",
    contract: "rollback(host, opts) -> outcome"
  }
)

verb(
  "kirikae",
  "run",
  {
    kind: :effect,
    shape: "run(plan, opts) -> outcome",
    laterals: ["error", "log", "process", "switch"],
    fleet: "kirikae",
    today: "exists:kirikae",
    meaning: "build and activate the planned system",
    wave: 0,
    origin: "E"
  }
)

verb(
  "kirikae",
  "verify",
  {
    kind: :effect,
    shape: "verify(desired, opts) -> Bool",
    laterals: ["switch", "validate"],
    fleet: "kirikae",
    today: "partial:kirikae",
    meaning: "current system resolves to the one built",
    wave: 0,
    origin: "E"
  }
)

edge("kirikae::run", :composes, "hyouka::build", "builds the system")
edge("kirikae::plan", :composes, "hyouka::plan", "switch is a nix build")
edge("kirikae::run", :composes, "kirikae::plan", "run executes the plan")
edge("kirikae::hold", :guards, "kirikae::decide", "backoff input")

edge(
  "kirikae::run",
  :guards,
  "kirikae::rollback",
  "run leaves a point to return to"
)

edge("kirikae::decide", :guards, "kirikae::run", "chooses act or hold")
edge("kirikae::verify", :guards, "kirikae::run", "proves the switch happened")

edge(
  "kirikae::run",
  :inverse,
  "kirikae::rollback",
  "activate the earlier system"
)

edge(
  "kirikae::rollback",
  :inverse,
  "kirikae::run",
  "activate the earlier system"
)

edge(
  "kirikae::list",
  :pairs,
  "kirikae::rollback",
  "rollback picks from the list"
)

edge("kirikae::record", :pairs, "kirikae::run", "every run leaves an entry")
edge("kirikae::plan", :requires, "gitto::info", "checkout state")

edge(
  "kirikae::rollback",
  :requires,
  "kirikae::list",
  "needs a target generation"
)

edge("kirikae::decide", :requires, "kirikae::record", "history feeds backoff")
