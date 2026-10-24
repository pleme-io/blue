space("tehai", {status: :ratified})

verb(
  "tehai",
  "list",
  {
    kind: :effect,
    shape: "list(declared, opts) -> [state]",
    laterals: ["deadline", "time"],
    fleet: "tehai",
    today: "partial:tehai",
    meaning: "every builder with live or stale state",
    wave: 0,
    origin: "E"
  }
)

verb(
  "tehai",
  "parse",
  {
    kind: :pure,
    shape: "parse(text) -> [machine]",
    laterals: ["validate"],
    fleet: "tehai",
    today: "exists:tehai",
    wave: 0,
    origin: "E"
  }
)

verb(
  "tehai",
  "probe",
  {
    kind: :effect,
    shape: "probe(machine, opts) -> checked",
    laterals: ["deadline", "process"],
    fleet: "tehai",
    today: "exists:tehai",
    wave: 0,
    origin: "E"
  }
)

verb(
  "tehai",
  "write",
  {
    kind: :effect,
    shape: "write(path, machines) -> nil",
    laterals: ["idempotent", "serialize"],
    fleet: "tehai",
    today: "partial:tehai",
    meaning: "write the live set atomically where nix reads it",
    wave: 0,
    origin: "E"
  }
)

edge("tehai::list", :composes, "tehai::parse", "declared set first")
edge("tehai::list", :composes, "tehai::probe", "probe each declared machine")
edge("tehai::probe", :guards, "tehai::write", "only live machines are written")

edge(
  "tehai::write",
  :inverse,
  "tehai::list",
  "write versus read of the live set"
)

edge(
  "tehai::list",
  :inverse,
  "tehai::write",
  "write versus read of the live set"
)

edge("tehai::probe", :refines, "hosuto?::reach?", "builder probe specialised")
edge("tehai::parse", :requires, "core::read", "reads the declared file")
edge("tehai::write", :requires, "tehai::probe", "only checked machines")
