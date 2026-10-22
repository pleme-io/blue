space("shisei", {status: :ratified})

verb(
  "shisei",
  "defaults",
  {
    kind: :pure,
    shape: "defaults(postures) -> entries",
    laterals: ["config"],
    fleet: nil,
    today: "exists:shisei",
    meaning: "the stance of a bare service",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shisei",
  "gated",
  {
    kind: :pure,
    shape: "gated(mode, sink, name, why, deny, allow) -> response",
    laterals: ["log", "switch"],
    fleet: "sekiban",
    today: "exists:shisei",
    meaning: "audit-or-enforce ladder for a refusing posture",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shisei",
  "posture",
  {
    kind: :decl,
    shape: "posture(name, table, defaults, layer) -> posture",
    laterals: ["config"],
    fleet: nil,
    today: "exists:shisei",
    meaning: "one named behaviour of a service with its fields",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shisei",
  "promote",
  {
    kind: :effect,
    shape: "promote(posture, mode, evidence) -> declaration",
    laterals: ["log", "switch"],
    fleet: "sekiban",
    today: "absent",
    meaning: "move a posture from audit to enforce on evidence",
    wave: 2,
    origin: "D",
    contract: "promote(posture, mode, opts) -> declaration"
  }
)

verb(
  "shisei",
  "rehearse",
  {
    kind: :effect,
    shape: "rehearse(posture, window) -> record",
    laterals: ["log", "switch", "time"],
    fleet: nil,
    today: "absent",
    meaning: "what enforcing would have refused in a past window",
    wave: 2,
    origin: "D"
  }
)

verb(
  "shisei",
  "serving",
  {
    kind: :pure,
    shape: "serving(postures, declaration, sink, handler) -> handler",
    laterals: ["config", "switch"],
    fleet: nil,
    today: "exists:shisei",
    meaning: "the whole composition: stance, refusals, handler",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shisei",
  "stack",
  {
    kind: :pure,
    shape: "stack(layers, handler) -> handler",
    laterals: ["config"],
    fleet: nil,
    today: "exists:shisei",
    meaning: "layers around a handler; first is outermost",
    wave: 0,
    origin: "D"
  }
)

verb(
  "shisei",
  "stance",
  {
    kind: :pure,
    shape: "stance(postures, declaration) -> record",
    laterals: ["config", "validate"],
    fleet: nil,
    today: "exists:shisei",
    meaning: "declaration over defaults, judged into accepted, off, refused",
    wave: 0,
    origin: "D"
  }
)

edge("shisei::stance", :composes, "kyohi::check", "refusals of entries")
edge("shisei::stance", :composes, "shisei::defaults", "laid over defaults")
edge("shisei::rehearse", :composes, "shisei::gated", "replay in audit mode")
edge("shisei::stack", :composes, "shisei::posture", "layers from postures")
edge("shisei::serving", :composes, "shisei::stack", "build the handler")
edge("shisei::serving", :composes, "shisei::stance", "judge then stack")

edge(
  "shisei::gated",
  :guards,
  "shisei::posture",
  "audit or enforce for refusals"
)

edge("shisei::posture", :pairs, "shisei::stance", "declared then judged")

edge(
  "shisei::promote",
  :refines,
  "shisei::gated",
  "moves a posture up the ladder"
)

edge("shisei::defaults", :requires, "shisei::posture", "one entry per posture")

edge(
  "shisei::promote",
  :requires,
  "shisei::rehearse",
  "evidence before enforcing"
)
