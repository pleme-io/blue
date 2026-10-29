space("saishikou", {status: :ratified})

verb(
  "saishikou",
  "retrying",
  {
    kind: :effect,
    shape: "retrying(policy, step) -> value",
    laterals: %w[retry error],
    fleet: nil,
    today: "exists:saishikou",
    wave: 0,
    origin: "H"
  }
)
