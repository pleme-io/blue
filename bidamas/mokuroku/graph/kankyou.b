space("kankyou", {status: :ratified})

verb(
  "kankyou",
  "get",
  {
    kind: :effect,
    shape: "get(name) -> text or nil",
    laterals: ["capability"],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "one environment variable, nil when unset",
    wave: 0,
    origin: "H"
  }
)
