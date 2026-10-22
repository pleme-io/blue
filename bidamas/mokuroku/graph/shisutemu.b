space("shisutemu", {status: :ratified})

verb(
  "shisutemu",
  "run",
  {
    kind: :effect,
    shape: "run(command, args, opts) -> result",
    laterals: ["process", "capability", "error"],
    fleet: nil,
    today: "partial:shisutemu",
    meaning: "run a command to completion; exec primitives exist, the verb does not",
    wave: 0,
    origin: "H"
  }
)
