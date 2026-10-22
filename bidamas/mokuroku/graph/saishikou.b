space("saishikou", {status: :ratified})

verb(
  "saishikou",
  "retrying",
  {
    kind: :effect,
    shape: "retrying(policy, step) -> value",
    laterals: ["retry", "error"],
    fleet: nil,
    today: "exists:saishikou",
    meaning: "call step again under a policy while it fails",
    wave: 0,
    origin: "H"
  }
)
